// Opt-in interoperability bridge. Inference remains in the Omega runner.
// Reuses the pinned llama.cpp UI, cpp-httplib and nlohmann/json.
#include "httplib.h"
#include "json.hpp"
#include <atomic>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <iostream>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <cstring>
#include <unistd.h>

using json = nlohmann::json;
using Clock = std::chrono::steady_clock;
extern char **environ;
static const char *OMEGA = "Omega-Astra-2026-11-04";
static constexpr auto QWEN = "build-mac/qwen.gguf";
// Drake's private voice fine-tune of the rung-10 checkpoint. Linux guest only; trained on "them: / me: " lines.
static constexpr auto VOICE = "Omega-Drake-Voice";
static constexpr auto VOICE_CK = "drake-voice.ck";
static constexpr auto LIMA = "/opt/homebrew/bin/limactl";
static std::atomic<bool> busy{false};
static std::atomic<unsigned> sequence{0};
static bool firmware = false;
static int ui_port = 8098;

static int firmware_socket(const char *name) {
    const char *home = getenv("HOME");
    if (!home) throw std::runtime_error("Home directory is unavailable");
    std::string path = std::string(home) + "/Applications/Omega/Aienux/" + name;
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (path.size() >= sizeof(addr.sun_path)) throw std::runtime_error("Aienux socket path is too long");
    std::strcpy(addr.sun_path, path.c_str());
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr))) {
        if (fd >= 0) close(fd);
        throw std::runtime_error("Open Aienux Omega.command to start the firmware model");
    }
    return fd;
}

static void reply(httplib::Response &res, const json &j, int status = 200) {
    res.status = status;
    res.set_content(j.dump(-1, ' ', false, json::error_handler_t::replace), "application/json");
}
static void error(httplib::Response &res, int status, const std::string &message) {
    reply(res, {{"error", {{"message", message}, {"type", "invalid_request_error"}, {"code", status}}}}, status);
}
static pid_t spawn(std::vector<std::string> args, int *output = nullptr) {
    int pipes[2] = {-1, -1};
    if (output && pipe(pipes)) throw std::runtime_error("Cannot create model output pipe");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    if (output) {
        posix_spawn_file_actions_adddup2(&actions, pipes[1], 1);
        posix_spawn_file_actions_addclose(&actions, pipes[0]);
        posix_spawn_file_actions_addclose(&actions, pipes[1]);
    } else posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    std::vector<char *> argv;
    for (auto &arg : args) argv.push_back(arg.data());
    argv.push_back(nullptr);
    pid_t pid = -1;
    int rc = posix_spawn(&pid, argv[0], &actions, nullptr, argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (output) {
        close(pipes[1]);
        if (rc) close(pipes[0]);
        else *output = pipes[0];
    }
    if (rc) throw std::runtime_error("Cannot start local model process");
    return pid;
}

struct Lease { ~Lease() { busy = false; } };
struct ModelProcess {
    pid_t pid = -1;
    int fd = -1;
    bool finished = false;
    std::string ticket = std::to_string(getpid()) + "-" + std::to_string(++sequence);
    unsigned wire_id = sequence.load();
    ~ModelProcess() {
        if (firmware) {
            if (fd < 0) return;
            // A disconnected generation cannot be reused as another request. Stop only this
            // experiment's private VM. Its read-only model disk survives; the launcher restarts it.
            try {
                int monitor = firmware_socket("monitor.sock");
                // UEFI Stall can busy-wait under TCG. Pause a completed VM between requests.
                write(monitor, finished ? "stop\n" : "quit\n", 5);
                close(monitor);
            } catch (...) {}
            close(fd);
            return;
        }
        if (pid < 0) return;
        try {
            // Only our generated ticket names a process group. User text is never shell code.
            auto cleanup = spawn({LIMA, "shell", "omega-llm", "sh", "-c",
                "f=/tmp/omega-ui-$1.pid; if [ -f \"$f\" ]; then "
                "p=$(cat \"$f\"); if [ \"$2\" = cancel ]; then /bin/kill -TERM -- \"-$p\" 2>/dev/null; fi; "
                "rm -f \"$f\"; fi", "sh", ticket, finished ? "done" : "cancel"});
            waitpid(cleanup, nullptr, 0);
        } catch (...) {}
        if (!finished) { kill(pid, SIGTERM); waitpid(pid, nullptr, 0); }
        if (fd >= 0) close(fd);
    }
    // Fixed checkpoint names only; never user text. The voice checkpoint is private and lives only in the guest.
    std::string checkpoint = "omega-v2-edited-20261104.ck";
    void start(const std::string &prompt, int tokens, int temp, unsigned seed) {
        if (firmware) {
            fd = firmware_socket("serial.sock");
            int monitor = firmware_socket("monitor.sock");
            if (write(monitor, "cont\n", 5) != 5) { close(monitor); throw std::runtime_error("Cannot resume Aienux"); }
            close(monitor);
            std::string hex;
            for (unsigned char c : prompt) { hex += "0123456789abcdef"[c >> 4]; hex += "0123456789abcdef"[c & 15]; }
            std::string command = "LM1 " + std::to_string(wire_id) + " " + std::to_string(tokens) + " " +
                std::to_string(temp) + " " + std::to_string(seed) + " " + hex + "\r";
            size_t sent = 0;
            while (sent < command.size()) {
                auto n = write(fd, command.data() + sent, command.size() - sent);
                if (n <= 0) throw std::runtime_error("Aienux console disconnected");
                sent += n;
            }
            return;
        }
        pid = spawn({LIMA, "shell", "omega-llm", "sh", "-c",
            "cd ~/omega && exec setsid --wait sh -c 'echo $$ > \"$1\"; shift; "
            "ck=$1; shift; exec timeout --foreground -k 2 120 ./ollm-ui sample \"$ck\" \"$@\" merges4096.bin' "
            "sh \"/tmp/omega-ui-$1.pid\" \"$6\" \"$2\" \"$3\" \"$4\" \"$5\"",
            "sh", ticket, std::to_string(seed), std::to_string(tokens), std::to_string(temp), prompt, checkpoint}, &fd);
    }
};

// Keep incomplete UTF-8 sequences until the next pipe read.
static size_t complete_utf8(const std::string &s) {
    if (s.empty()) return 0;
    size_t start = s.size() - 1;
    while (start && (static_cast<unsigned char>(s[start]) & 0xc0) == 0x80) --start;
    unsigned char c = s[start];
    size_t need = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : c >= 0xc0 ? 2 : 1;
    return s.size() - start < need ? start : s.size();
}

// Calls emit with new decoded text and with empty strings for keep-alives.
static int generate(ModelProcess &p, const std::function<bool(const std::string &)> &emit) {
    auto begin = Clock::now();
    auto heartbeat = begin;
    std::string pending;
    std::string wire;
    auto data_prefix = "LMDATA " + std::to_string(p.wire_id) + " ";
    for (;;) {
        if (Clock::now() - begin > std::chrono::seconds(firmware ? 1200 : 125)) return 124;
        pollfd poller{p.fd, POLLIN, 0};
        int ready = poll(&poller, 1, 200);
        if (ready < 0 && errno != EINTR) return 1;
        if (ready > 0) {
            char buf[4096];
            auto count = read(p.fd, buf, sizeof(buf));
            if (count <= 0) { if (firmware) return 1; break; }
            if (firmware) {
                wire.append(buf, count);
                if (wire.size() > 32768) return 1;
                size_t end;
                while ((end = wire.find('\n')) != std::string::npos) {
                    auto line = wire.substr(0, end); wire.erase(0, end + 1);
                    if (!line.empty() && line.back() == '\r') line.pop_back();
                    if (line == "LMDONE " + std::to_string(p.wire_id)) {
                        p.finished = true;
                        if (!pending.empty() && !emit(pending)) return 130;
                        return 0;
                    }
                    if (line.rfind("LMERR ", 0) == 0) { p.finished = true; return 1; }
                    if (line.rfind(data_prefix, 0) != 0) continue;
                    auto hex = line.substr(data_prefix.size());
                    if (hex.size() % 2) return 1;
                    auto nibble = [](char c) -> int { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1; };
                    for (size_t k = 0; k < hex.size(); k += 2) {
                        int a = nibble(hex[k]), b = nibble(hex[k + 1]);
                        if (a < 0 || b < 0) return 1;
                        pending += char(a * 16 + b);
                    }
                }
            } else pending.append(buf, count);
            auto length = complete_utf8(pending);
            if (length && !emit(pending.substr(0, length))) return 130;
            pending.erase(0, length);
        }
        if (Clock::now() - heartbeat >= std::chrono::seconds(1)) {
            if (!emit("")) return 130;
            heartbeat = Clock::now();
        }
    }
    int status = 0;
    waitpid(p.pid, &status, 0);
    p.finished = true;
    if (!pending.empty() && !emit(pending)) return 130;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static json model(const std::string &id) {
    return {{"id", id}, {"name", id}, {"object", "model"}, {"owned_by", "local"},
        {"created", 0}, {"path", ""}, {"in_cache", false}, {"aliases", json::array({id})},
        {"status", {{"value", "loaded"}, {"args", json::array()}}},
        {"architecture", {{"input_modalities", {"text"}}, {"output_modalities", {"text"}}}}};
}
static json upstream_props() {
    httplib::Client client("127.0.0.1", 8097);
    client.set_connection_timeout(2);
    auto r = client.Get("/props");
    if (!r || r->status != 200) throw std::runtime_error("Start Qwen through Omega to load the llama UI");
    return json::parse(r->body);
}

// Drake's reply ends where the other person's next line (or a blank line) begins. Later bubbles drop "me:".
static std::string voice_reply(const std::string &raw) {
    std::string out;
    size_t at = 0;
    bool first = true;
    while (at < raw.size()) {
        size_t nl = raw.find('\n', at);
        if (nl == std::string::npos) nl = raw.size();
        auto line = raw.substr(at, nl - at);
        at = nl + 1;
        if (!first) {
            if (line.empty() || line.rfind("me:", 0) != 0) break;
            line.erase(0, 3);
        }
        while (!line.empty() && line.front() == ' ') line.erase(0, 1);
        if (!line.empty()) out += (out.empty() ? "" : "\n") + line;
        first = false;
    }
    return out;
}

static void completion(const httplib::Request &req, httplib::Response &res) {
    json body = json::parse(req.body);
    auto selected = body.value("model", std::string(OMEGA));
    if (selected == QWEN) {
        const bool streaming = body.value("stream", false);
        if (streaming) {
            auto data = body.dump();
            res.set_chunked_content_provider("text/event-stream", [data](size_t, httplib::DataSink &sink) {
                httplib::Client client("127.0.0.1", 8097);
                client.set_read_timeout(130);
                auto r = client.Post("/v1/chat/completions", {}, data, "application/json",
                    [&](const char *bytes, size_t count) { return sink.write(bytes, count); });
                if (!r || r->status != 200) {
                    std::string e = "data: " + json({{"error", {{"message", "Qwen request failed"}}}}).dump() + "\n\n";
                    sink.write(e.data(), e.size());
                }
                sink.done();
                return true;
            });
        } else {
            httplib::Client client("127.0.0.1", 8097);
            client.set_read_timeout(130);
            auto r = client.Post("/v1/chat/completions", body.dump(), "application/json");
            if (!r) { error(res, 502, "Qwen is unavailable"); return; }
            res.status = r->status;
            res.set_content(r->body, "application/json");
        }
        return;
    }
    const bool voice = !firmware && selected == VOICE;
    if (selected != OMEGA && !voice) { error(res, 404, "Unknown local model"); return; }
    for (auto key : {"tools", "stop", "grammar", "response_format"}) {
        if (body.contains(key) && !body[key].is_null() && !body[key].empty()) {
            error(res, 400, std::string("Omega's story model does not support ") + key); return;
        }
    }
    if (body.value("n", 1) != 1) { error(res, 400, "Omega supports one completion at a time"); return; }
    std::string prompt;
    if (!body.contains("messages") || !body["messages"].is_array()) { error(res, 400, "messages must be an array"); return; }
    for (const auto &message : body["messages"]) {
        auto role = message.value("role", std::string());
        if (role != "user" && role != "assistant" && role != "system") { error(res, 400, "Omega accepts text messages only"); return; }
        auto content = message.at("content");
        std::string text;
        if (content.is_string()) text = content.get<std::string>();
        else if (content.is_array()) {
            for (const auto &part : content) {
                if (part.value("type", "") != "text") { error(res, 400, "Omega accepts text only"); return; }
                text += part.at("text").get<std::string>();
            }
        } else { error(res, 400, "Message content must be text"); return; }
        if (text.empty()) continue;
        if (voice) {
            if (role == "system") continue;
            // Same shape as the training text: one "them: " or "me: " line per text bubble.
            std::string who = role == "user" ? "them: " : "me: ";
            size_t at = 0;
            while (at <= text.size()) {
                size_t nl = text.find('\n', at);
                if (nl == std::string::npos) nl = text.size();
                auto line = text.substr(at, nl - at);
                if (!line.empty()) prompt += who + line + "\n";
                at = nl + 1;
            }
            continue;
        }
        if (!prompt.empty()) prompt += "\n";
        prompt += text;
    }
    if (voice && !prompt.empty()) {
        // The checkpoint sees 256 tokens. Keep the latest lines and ask for Drake's reply.
        if (prompt.size() > 700) { auto cut = prompt.find('\n', prompt.size() - 700); prompt = prompt.substr(cut == std::string::npos ? 0 : cut + 1); }
        prompt += "me:";
    }
    if (prompt.empty() || prompt.size() > 4000 || prompt.find('\0') != std::string::npos) {
        error(res, 400, "Enter a story beginning or shorten this conversation to at most 4000 UTF-8 bytes"); return;
    }
    if (firmware && (prompt.size() > 159 || std::any_of(prompt.begin(), prompt.end(), [](unsigned char c) { return c < 32 || c > 126; }))) {
        error(res, 400, "Aienux currently accepts one story beginning of up to 159 plain ASCII characters. Start a new chat for each prompt."); return;
    }
    int tokens = body.value("max_tokens", 64);
    if (body.contains("max_completion_tokens") && !body["max_completion_tokens"].is_null()) tokens = body["max_completion_tokens"].get<int>();
    if (tokens == -1) tokens = 64;
    if (tokens < 1 || tokens > 128) { error(res, 400, "Set maximum output tokens between 1 and 128 for Omega"); return; }
    if (firmware) tokens = std::min(tokens, 8);
    double temperature = body.value("temperature", 0.8);
    if (!std::isfinite(temperature) || temperature < 0 || temperature > 2) { error(res, 400, "Temperature must be between 0 and 2"); return; }
    int seed = body.value("seed", 42);
    if (seed < 0) seed = 42;
    bool streaming = body.value("stream", false);
    bool expected = false;
    if (!busy.compare_exchange_strong(expected, true)) { error(res, 429, "Omega is already generating. Stop that response or wait for it to finish."); return; }
    auto lease = std::make_shared<Lease>();
    auto child = std::make_shared<ModelProcess>();
    if (voice) child->checkpoint = VOICE_CK;
    child->start(prompt, tokens, int(temperature * 1000), unsigned(seed));
    std::string id = "omega-" + child->ticket;
    auto created = std::time(nullptr);
    std::string served = voice ? VOICE : OMEGA;
    auto chunk = [id, created, served](const json &delta, const json &reason = nullptr) {
        return json{{"id", id}, {"object", "chat.completion.chunk"}, {"created", created}, {"model", served},
            {"choices", json::array({{{"index", 0}, {"delta", delta}, {"finish_reason", reason}}})}};
    };
    if (streaming) {
        res.set_header("Cache-Control", "no-cache");
        auto closed = req.is_connection_closed;
        res.set_chunked_content_provider("text/event-stream", [lease, child, chunk, closed, voice](size_t, httplib::DataSink &sink) {
            auto send = [&](const json &j) {
                auto s = "data: " + j.dump(-1, ' ', false, json::error_handler_t::replace) + "\n\n";
                return !closed() && sink.write(s.data(), s.size());
            };
            if (!send(chunk({{"role", "assistant"}, {"content", ""}}))) return false;
            std::string held;
            int rc = generate(*child, [&](const std::string &text) {
                if (closed()) return false;
                if (voice && !text.empty()) { held += text; return true; }
                return text.empty() ? sink.write(": generating\n\n", 14) : send(chunk({{"content", text}}));
            });
            if (rc == 130) return false;
            if (voice && !rc && !send(chunk({{"content", voice_reply(held)}}))) return false;
            if (rc) send(chunk({{"content", "\n\n[Omega runtime error: generation failed or timed out. Try a shorter story beginning.]"}}));
            else send(chunk(json::object(), "stop"));
            sink.write("data: [DONE]\n\n", 14);
            sink.done();
            return true;
        });
    } else {
        std::string text;
        int rc = generate(*child, [&](const std::string &part) { text += part; return !req.is_connection_closed(); });
        if (rc) { error(res, 502, "Omega generation failed or timed out"); return; }
        if (voice) text = voice_reply(text);
        reply(res, {{"id", id}, {"object", "chat.completion"}, {"created", created}, {"model", served},
            {"choices", json::array({{{"index", 0}, {"message", {{"role", "assistant"}, {"content", text}}}, {"finish_reason", "stop"}}})}});
    }
}

int main(int argc, char **argv) {
    if ((argc != 2 && argc != 3) || std::string(argv[1]) != "--enable-local-ui-bridge" ||
        (argc == 3 && std::string(argv[2]) != "--aienux")) {
        std::cerr << "Opt in with --enable-local-ui-bridge\n"; return 2;
    }
    firmware = argc == 3;
    if (firmware) { ui_port = 8099; OMEGA = "Omega-Astra-Aienux"; }
    signal(SIGPIPE, SIG_IGN);
    httplib::Server server;
    server.set_payload_max_length(65536);
    server.set_read_timeout(10);
    server.set_write_timeout(10);
    server.set_exception_handler([](const auto &, auto &res, std::exception_ptr exception) {
        try { std::rethrow_exception(exception); }
        catch (const json::exception &) { error(res, 400, "Invalid JSON or parameter type"); }
        catch (const std::exception &e) { error(res, 503, e.what()); }
    });
    server.set_pre_routing_handler([](const auto &req, auto &res) {
        // Local UI only. Do not admit arbitrary websites through permissive CORS.
        auto host = req.get_header_value("Host");
        if (host != "127.0.0.1:" + std::to_string(ui_port) && host != "localhost:" + std::to_string(ui_port)) {
            error(res, 403, "Only the local Omega host is allowed");
            return httplib::Server::HandlerResponse::Handled;
        }
        if (req.has_header("Origin")) {
            auto origin = req.get_header_value("Origin");
            if (origin != "http://127.0.0.1:" + std::to_string(ui_port) && origin != "http://localhost:" + std::to_string(ui_port)) {
                error(res, 403, "Only the local Omega UI is allowed");
                return httplib::Server::HandlerResponse::Handled;
            }
        }
        return httplib::Server::HandlerResponse::Unhandled;
    });
    server.Get("/health", [](const auto &, auto &res) { reply(res, {{"status", "ok"}, {"service", "omega-ui-bridge"}, {"runtime", firmware ? "aienux-firmware" : "linux"}, {"omega_busy", busy.load()}}); });
    server.Get("/v1/models", [](const auto &, auto &res) { reply(res, {{"object", "list"}, {"data", firmware ? json::array({model(OMEGA), model(QWEN)}) : json::array({model(OMEGA), model(VOICE), model(QWEN)})}}); });
    server.Get("/props", [](const auto &req, auto &res) {
        auto props = upstream_props();
        auto selected = req.get_param_value("model");
        if (selected.empty()) props["role"] = "router";
        else if (selected != OMEGA && selected != QWEN && (firmware || selected != VOICE)) { error(res, 404, "Unknown model"); return; }
        if (selected != QWEN) {
            props["model_alias"] = selected == VOICE ? VOICE : OMEGA;
            props["model_path"] = selected == VOICE ? VOICE : OMEGA;
            props.erase("model_ftype");
            props["bos_token"] = "";
            props["eos_token"] = "";
            props["default_generation_settings"]["params"]["max_tokens"] = firmware ? 8 : 64;
            props["default_generation_settings"]["params"]["n_predict"] = firmware ? 8 : 64;
            props["default_generation_settings"]["params"]["seed"] = 42;
            props["default_generation_settings"]["n_ctx"] = 256;
            props["chat_template"] = "{% for message in messages %}{{ message.content }}{% endfor %}";
            props["chat_template_caps"] = {{"supports_tools", false}, {"supports_tool_calls", false}, {"supports_system_role", false}};
            props["ui_settings"] = {{"max_tokens", firmware ? 8 : 64}, {"enableDiscoverModels", false}, {"titleGenerationUseLLM", false}};
        }
        props["endpoint_slots"] = false;
        reply(res, props);
    });
    server.Get("/slots", [](const auto &, auto &res) { reply(res, json::array()); });
    server.Get("/tools", [](const auto &, auto &res) { reply(res, {{"tools", json::array()}}); });
    server.Get("/models/sse", [](const auto &req, auto &res) {
        auto closed = req.is_connection_closed;
        res.set_chunked_content_provider("text/event-stream", [closed](size_t, httplib::DataSink &sink) {
            if (closed()) return false;
            if (!sink.write(": local models ready\n\n", 22)) return false;
            std::this_thread::sleep_for(std::chrono::seconds(2));
            return true;
        });
    });
    server.Post("/v1/chat/completions", completion);
    server.Post("/models/load", [](const auto &, auto &res) { reply(res, {{"success", true}}); });
    // Reuse the already-running llama UI assets without changing its files.
    server.Get("/.*", [](const auto &req, auto &res) {
        if (req.path.rfind("/v1/", 0) == 0 || req.path.rfind("/models/", 0) == 0) { error(res, 404, "Endpoint unavailable in local bridge"); return; }
        httplib::Client client("127.0.0.1", 8097);
        client.set_decompress(false);
        httplib::Headers headers{{"Accept-Encoding", "gzip"}};
        auto r = client.Get(req.target, headers);
        if (!r) { error(res, 502, "Start Qwen through Omega to load the llama UI"); return; }
        res.status = r->status;
        res.set_content(r->body, r->get_header_value("Content-Type"));
        if (r->has_header("Content-Encoding")) res.set_header("Content-Encoding", r->get_header_value("Content-Encoding"));
    });
    std::cout << "Omega + Qwen llama UI: http://127.0.0.1:" << ui_port << (firmware ? " (Aienux firmware)" : " (Linux)") << "\n" << std::flush;
    return server.listen("127.0.0.1", ui_port) ? 0 : 1;
}
