#!/bin/sh
# Explicit, temporary Mac host compatibility experiment. Not an Omega-native runtime.
set -eu
[ "$#" = 1 ] || { echo 'usage: build.sh OUTPUT_DIRECTORY' >&2; exit 2; }
out=$1
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
mkdir -p "$out/deps"
base=https://raw.githubusercontent.com/ggml-org/llama.cpp/7aca0d2ea8d92b56911233b822db01f9fbb1ae50/vendor
fetch() {
 file=$1 url=$2 hash=$3
 if [ ! -f "$out/deps/$file" ]; then curl --fail --location "$url" -o "$out/deps/$file"; fi
 actual=$(shasum -a 256 "$out/deps/$file" | cut -d' ' -f1)
 [ "$actual" = "$hash" ] || { echo "dependency digest mismatch: $file" >&2; exit 65; }
}
fetch httplib.h "$base/cpp-httplib/httplib.h" a595e3f0d864e1606f9455ed4a8738de66fc8ef4abf7164e6570fe0e0393080b
fetch httplib.cpp "$base/cpp-httplib/httplib.cpp" 516c58994baa9bcc3b5616f453710c0b4d2d341ac473f788fcfb029f8548caa5
fetch json.hpp "$base/nlohmann/json.hpp" 08f19bbcc66ff3082f5caf58867b1232987dba98d82e2b29d870722fce42776b
curl --fail --location "$base/cpp-httplib/LICENSE" -o "$out/deps/httplib-LICENSE"
# nlohmann/json's MIT notice is embedded in json.hpp. Keep both notices with the binary.
c++ -std=c++17 -O1 -pthread -Wall -Wextra -I "$out/deps" \
 "$here/bridge.cpp" "$out/deps/httplib.cpp" -o "$out/omega-ui-bridge"
shasum -a 256 "$out/omega-ui-bridge"
