#!/bin/sh
# chat1-render.sh REQ.json: the CHAT1 conversation text of one OpenAI chat request on stdout,
# specials written as their marker strings (<|doc|> ... ending in the generation prompt
# <|assistant|>). `ollm-tok tokenc chat` on it gives the CHAT1 token count when no content holds
# a marker string (checked: exit 3 otherwise). An approximation of `ollm chatenc` (serve4
# sibling) used only until that command lands; tools are jq's compact re-serialization; content
# parts arrays are joined with no separator (as serve.om does).
set -u
if grep -q '<|' "$1"; then echo "chat1-render: marker string in content" >&2; exit 3; fi
exec jq -j 'def txt: if type == "array" then map(.text) | join("") elif . == null then "" else . end; . as $r | "<|doc|>" +
 ( [ (if ($r.tools // []) != [] and ($r.messages[0].role != "system") then
       "<|system|>\n\n# Tools\n" + ($r.tools|tojson) + "<|end|>" else empty end),
     ($r.messages[] |
      if .role == "system" then "<|system|>" + (.content|txt) +
          (if ($r.tools // []) != [] then "\n\n# Tools\n" + ($r.tools|tojson) else "" end) + "<|end|>"
      elif .role == "user" then "<|user|>" + (.content|txt) + "<|end|>"
      elif .role == "assistant" then "<|assistant|>" + (.content|txt) +
          ([.tool_calls[]? | "<|tool_call|>{\"name\":" + (.function.name|tojson) + ",\"arguments\":" +
            (.function.arguments | if type == "string" then fromjson|tojson else tojson end) + "}"] | join("")) + "<|end|>"
      elif .role == "tool" then "<|tool_result|>" + (.content|txt) + "<|end|>"
      else error("role " + .role) end) ] | join("") ) + "<|assistant|>"' "$1"
