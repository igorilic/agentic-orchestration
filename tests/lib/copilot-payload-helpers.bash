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

# mock_confidence_scorer <dir> <band> <score> <gates_json>
# Writes a stub confidence.sh into <dir>/.github/hooks/scripts/confidence.sh
# that returns the given band/score/gates without running the real scorer.
# Usage: mock_confidence_scorer "$SANDBOX" "GREEN" 80 '[]'
mock_confidence_scorer() {
  local project_dir="$1"
  local band="$2"
  local score="$3"
  local gates="${4:-[]}"
  local scorer_path="$project_dir/.github/hooks/scripts/confidence.sh"
  mkdir -p "$(dirname "$scorer_path")"
  cat > "$scorer_path" <<STUB
#!/usr/bin/env bash
printf '{"band":"%s","score":%s,"gates":%s}\n' "$band" "$score" '$gates'
STUB
  chmod +x "$scorer_path"
}
