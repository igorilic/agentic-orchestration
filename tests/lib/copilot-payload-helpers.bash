#!/usr/bin/env bash
# Helpers for COP-2 Copilot dispatcher tests.
# Produces synthetic Copilot CLI stdin payloads for piping into the dispatcher.

# mk_payload <toolName> <command> <cwd>
# Emits a JSON object matching the Copilot CLI preToolUse stdin contract.
# toolArgs is double-encoded: the inner object is serialised to a JSON string
# before being embedded in the outer object.
mk_payload() {
  local tool_name="$1"
  local command="$2"
  local cwd="$3"
  jq -nc \
    --arg t "$tool_name" \
    --arg c "$command" \
    --arg d "$cwd" \
    '{toolName:$t, toolArgs:({command:$c} | tojson), cwd:$d, timestamp:1714694400000}'
}
