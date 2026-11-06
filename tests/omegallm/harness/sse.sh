#!/bin/sh
# sse.sh call ID NAME ARGS_JSON | sse.sh text ID CONTENT: one scripted streamed chat completion
# (OpenAI chunk shape) on stdout, for respond.sh scripts. Fixture only, never model output.
set -u
kind=$1 id=$2
chunk() { printf 'data: %s\n\n' "$1"; }
h='"id":"chatcmpl-'$id'","object":"chat.completion.chunk","created":0,"model":"ollm"'
if [ "$kind" = call ]; then
	chunk "{$h,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":null}]}"
	tc=$(jq -nc --arg id "call_${id}_0" --arg n "$3" --arg a "$4" '[{index:0,id:$id,type:"function",function:{name:$n,arguments:$a}}]')
	chunk "{$h,\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":$tc},\"finish_reason\":null}]}"
	fin=tool_calls
else
	c=$(jq -nc --arg c "$3" '$c')
	chunk "{$h,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":$c},\"finish_reason\":null}]}"
	fin=stop
fi
chunk "{$h,\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"$fin\"}]}"
chunk "{$h,\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"
chunk "[DONE]"
