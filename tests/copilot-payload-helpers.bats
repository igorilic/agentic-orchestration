#!/usr/bin/env bats
# Tests for tests/lib/copilot-payload-helpers.bash
# COP-2 Step 1: payload fixture helper

LIB="$BATS_TEST_DIRNAME/lib/copilot-payload-helpers.bash"

setup() {
  load "$LIB"
}

@test "mk_payload produces valid JSON parseable by jq" {
  run bash -c "source '$LIB'; mk_payload 'bash' 'git status' '/tmp/x' | jq -e ."
  [ "$status" -eq 0 ]
}

@test "mk_payload sets toolName correctly" {
  run bash -c "source '$LIB'; mk_payload 'bash' 'git status' '/tmp/x' | jq -e '.toolName == \"bash\"'"
  [ "$status" -eq 0 ]
}

@test "mk_payload sets command inside double-encoded toolArgs" {
  run bash -c "source '$LIB'; mk_payload 'bash' 'git status' '/tmp/x' | jq -e '(.toolArgs | fromjson | .command) == \"git status\"'"
  [ "$status" -eq 0 ]
}

@test "mk_payload toolArgs is a string, not an object (double-encoded shape)" {
  run bash -c "source '$LIB'; mk_payload 'bash' 'git status' '/tmp/x' | jq -e '(.toolArgs | type) == \"string\"'"
  [ "$status" -eq 0 ]
}
