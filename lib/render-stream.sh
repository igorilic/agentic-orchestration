#!/usr/bin/env bash
# =============================================================================
# lib/render-stream.sh  —  SDK-1 LIVE PIPELINE RENDERER
#
# Reads sentinel events from stdin, renders a flat indented stream in the
# terminal with an animated spinner on the current ACTIVE line.  Non-TTY
# output is plain text with no ANSI escapes.
#
# SDK-1 Step B-1: ported from spikes/sdk-1-renderer/render.sh — mechanics
# are UNCHANGED (FIFO/ticker spinner, --plain/non-TTY fallback, --force-tty
# test hook, the done-event embedded-`|` fix, all six event handlers). The
# only difference is colors are sourced from lib/common.sh instead of being
# duplicated (spikes/sdk-1-renderer/FINDINGS.md confirmed the spike's
# hardcoded palette was already byte-identical to lib/common.sh's, and the
# spinner frames already matched lib/pipeline-core.sh's).
#
# SENTINEL GRAMMAR
# ────────────────
# Prefix: @@ANW|   Field separator: |   Non-sentinel lines silently discarded.
#
#   @@ANW|phase|<agent>|<tier>
#       Start a new agent section.  Prints "▸ <agent> · <tier>" header.
#       Finalises any existing ACTIVE spinner line first.
#
#   @@ANW|step|run|<text>
#       Begin an ACTIVE spinner line.  <text> is displayed while spinning.
#       Finalises any existing ACTIVE line first (treat as implicit ok).
#
#   @@ANW|step|ok|<text>
#       Finalise the current ACTIVE line as "⏺ <text>".
#       If no ACTIVE line, print "⏺ <text>" immediately.
#
#   @@ANW|step|fail|<text>
#       Finalise the current ACTIVE line as "✗ <text>".
#       If no ACTIVE line, print "✗ <text>" immediately.
#
#   @@ANW|deleg|<tier>|<text>
#       Finalise the current ACTIVE line as "⏺ <active_text>  [DELEGATED]",
#       then print a nested "↳ sidekick · <tier>: <text>" line.
#
#   @@ANW|deleg_reject|<tier>|<text>
#       Print a nested "❌ sidekick · <tier>: <text>" rejection line.
#       Does NOT change ACTIVE state (parent remains idle or active).
#
#   @@ANW|verdict|<band>|<score>
#       Print a per-section verdict line.  <band> = GREEN | YELLOW | RED.
#
#   @@ANW|done|<text>
#       Finalise any ACTIVE line, then print "✓ <text>" as the final summary.
#
# NON-TTY FALLBACK
# ────────────────
# When stdout is not a TTY (or --plain is passed) all ANSI escapes, carriage-
# return overwrites, and spinner animation are suppressed.  run steps are
# buffered and printed only when finalised (ok / fail / deleg).
#
# CRUX MECHANIC
# ─────────────
# TTY path uses a FIFO opened read+write (exec 3<>FIFO) so the write-end
# remains open indefinitely.  macOS ships bash 3.2 which only supports
# integer read -t timeouts.  Instead of fractional -t, a background TICKER
# process writes @@ANW|__TICK__ to the same FIFO every 0.2 s; the main loop
# uses a safe integer read -t 5 that rarely fires.  On each tick the spinner
# frame is redrawn via \r.  On each real event the line is first cleared
# (\r+spaces), processed, and the spinner re-rendered if a step is active.
#
# BASH BACKGROUND JOB STDIN GOTCHA (key spike finding):
# bash redirects stdin of async (&) jobs to /dev/null in non-interactive
# shells.  The feeder uses `cat <&4` (where fd 4 = saved stdin) rather than
# plain `cat` to work around this.  See `exec 4<&0` in main().
#
# USAGE
#   fake-pipeline.sh | render-stream.sh           # live TTY mode
#   fake-pipeline.sh | render-stream.sh --plain   # plain / non-TTY mode
# =============================================================================

set -euo pipefail

# ── Arg parsing ──────────────────────────────────────────────────────────────
FORCE_PLAIN=false
FORCE_TTY=false
for _arg in "$@"; do
  case "$_arg" in
    --plain)     FORCE_PLAIN=true ;;
    --force-tty) FORCE_TTY=true  ;;  # for testing TTY path without a real TTY
  esac
done

# ── TTY detection ────────────────────────────────────────────────────────────
IS_TTY=false
if { [ -t 1 ] || $FORCE_TTY; } && ! $FORCE_PLAIN; then
  IS_TTY=true
fi

# ── Colors (reuse lib/common.sh; empty strings in non-TTY mode) ──────────────
# Resolve this script's own directory so common.sh is found regardless of
# the caller's working directory — works both when run standalone (as in
# the bats test) and when later invoked/sourced by the orchestrator.
_RENDER_STREAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "$_RENDER_STREAM_DIR/common.sh"
if ! $IS_TTY; then
  RED='' GREEN='' YELLOW='' CYAN='' MAGENTA='' BOLD='' DIM='' NC=''
fi

# ── Milestones persistence (SDK-1 Step B-4) ─────────────────────────────────
# ponytail: source lib/milestones.sh the same way common.sh is resolved above
# (relative to this script, not the caller's cwd) so append_milestone works
# regardless of where the orchestrator invokes the renderer from.
# shellcheck source=lib/milestones.sh disable=SC1091
source "$_RENDER_STREAM_DIR/milestones.sh"

# ponytail: identity (spec_id/pipeline_step/agent/tier) is orchestrator-
# injected env per spec OQ-2 — authoritative over anything a `phase` sentinel
# line carries (the agent doesn't know its own spec_id/pipeline_step). Read
# once at startup rather than re-reading env on every event.
AW_SPEC_ID="${AW_SPEC_ID:-}"
AW_PIPELINE_STEP="${AW_PIPELINE_STEP:-}"
AW_AGENT="${AW_AGENT:-}"
AW_TIER="${AW_TIER:-}"

# ── Spinner frames (LOCAL — identical to lib/pipeline-core.sh:150; kept
#    local rather than sourcing pipeline-core.sh, which is the orchestrator
#    and carries set/trap side effects) ───────────────────────────────────
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
SPINNER_IDX=0

# ── Renderer state ───────────────────────────────────────────────────────────
ACTIVE_TEXT=""       # text of current in-progress step; empty = no active step
ACTIVE_START=0       # epoch second when the current step started
STREAM_START=$(date +%s)  # B-7 close-out F1: epoch for the idle heartbeat's
                           # elapsed time, captured once here rather than at
                           # first tick — so elapsed reflects time since the
                           # renderer started, not time since the first frame.
DELEG_PARENT_TEXT=""  # SDK-1 B-4: the parent step's text a deleg hangs under.
                       # Captured from ACTIVE_TEXT at deleg-time, BEFORE
                       # finalize_active clears it — deleg_reject (which per
                       # the grammar does NOT touch ACTIVE_TEXT) reuses this
                       # same tracked value so its milestone still records
                       # the right parent even though ACTIVE_TEXT is empty
                       # by then.

# ── Helpers ──────────────────────────────────────────────────────────────────

tier_color() {
  # Returns the ANSI color escape for a model tier (empty in non-TTY mode).
  # Use tr for uppercase; ${var^^} requires bash 4+, macOS ships bash 3.2.
  local tier
  tier=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
  case "$tier" in
    OPUS)   printf '%s' "$MAGENTA" ;;
    SONNET) printf '%s' "$CYAN"    ;;
    HAIKU)  printf '%s' "$GREEN"   ;;
    *)      printf '%s' "$BOLD"    ;;
  esac
}

elapsed_str() {
  local start="$1"
  local now
  now=$(date +%s)
  local diff=$(( now - start ))
  local mins=$(( diff / 60 ))
  local secs=$(( diff % 60 ))
  printf "%dm%02ds" "$mins" "$secs"
}

clear_line() {
  # Erase the current terminal line (TTY only).
  if $IS_TTY; then
    printf "\r%80s\r" ""
  fi
}

render_active() {
  # Redraw the spinner line in place (TTY only).
  if ! $IS_TTY; then return; fi
  local frame="${SPINNER_FRAMES[$((SPINNER_IDX % ${#SPINNER_FRAMES[@]}))]}"
  SPINNER_IDX=$(( SPINNER_IDX + 1 ))
  if [ -z "$ACTIVE_TEXT" ]; then
    # ponytail: idle heartbeat — no step is active (e.g. troubleshooter
    # emits no sentinels at all, or any agent is still starting up), so
    # draw a heartbeat line instead of leaving the screen blank. B-7
    # removed the old generic spinner_start/spinner_stop (AC-7); this is
    # the sentinel renderer's own replacement for that idle-time signal.
    local elapsed
    elapsed=$(elapsed_str "$STREAM_START")
    printf "\r  ${MAGENTA}%s${NC} ${BOLD}▸ %s${NC} · %s ${DIM}(%s)${NC}   " \
      "$frame" "${AW_AGENT:-agent}" "${AW_TIER:-}" "$elapsed"
    return
  fi
  local elapsed
  elapsed=$(elapsed_str "$ACTIVE_START")
  printf "\r  ${MAGENTA}%s${NC} %s ${DIM}(%s)${NC}   " \
    "$frame" "$ACTIVE_TEXT" "$elapsed"
}

finalize_active() {
  # Print the final form of the active line and clear ACTIVE state.
  # Args: <mode: ok|fail|delegated> [<display_text>]
  local mode="$1"
  local text="${2:-$ACTIVE_TEXT}"
  clear_line
  case "$mode" in
    ok)
      printf "  ${GREEN}⏺${NC} %s\n" "$text"
      ;;
    fail)
      printf "  ${RED}✗${NC} %s\n" "$text"
      ;;
    delegated)
      printf "  ${GREEN}⏺${NC} %s  ${DIM}[DELEGATED]${NC}\n" "$text"
      ;;
  esac
  ACTIVE_TEXT=""
  ACTIVE_START=0
}

record_milestone() {
  # SDK-1 Step B-4: thin wrapper over append_milestone closing over the
  # env-injected identity so each event handler below doesn't repeat it.
  # Args: <event> <status> <text> <delegated_to> <parent_text>
  # ponytail: `|| true` — a milestone-write failure (e.g. AW_SPEC_ID unset,
  # as in the B-1/B-2 golden tests, which reject via append_milestone's own
  # spec_id guard) must never crash the renderer; rendering is the primary
  # job, milestones.jsonl is a side-write. No arity re-validation here — B-2
  # already dropped malformed lines before any handle_event case reaches
  # this call.
  append_milestone "$1" "$AW_SPEC_ID" "$AW_PIPELINE_STEP" "$AW_AGENT" "$AW_TIER" \
    "$2" "$3" "$4" "$5" || true
}

# ── Event handler ─────────────────────────────────────────────────────────────
handle_event() {
  local line="$1"

  # Silently discard non-sentinel lines (in production these go to audit.log)
  [[ "$line" == @@ANW\|* ]] || return 0

  # Parse: strip @@ANW| prefix, split into evtype | f1 | f2 (f2 = remainder)
  local raw="${line#@@ANW|}"
  local evtype="${raw%%|*}"

  # SDK-1 Step B-2 (OQ-1 arity validation): has_arg / has_arg2 record whether
  # a field is genuinely PRESENT (a "|" separator was seen), not merely
  # whether the derived variable happens to be non-empty. This matters
  # because bash's "${var#*|}" and "${var%%|*}" leave a string UNCHANGED
  # when the pattern (a "|") isn't found — so a line with a missing field
  # (e.g. "@@ANW|step|run", no third field) would otherwise silently reuse
  # the status keyword AS the free-text field ("⏺ run" — the exact
  # mis-render documented as spike gap #1 in FINDINGS.md). Computing
  # presence explicitly lets every event handler drop malformed/arity-short
  # lines instead of mis-rendering them, per the spec's OQ-1 decision.
  local has_arg=false
  [[ "$raw" == *"|"* ]] && has_arg=true

  local payload=""
  $has_arg && payload="${raw#*|}"
  local rest="$payload"   # raw remainder after evtype — correct value for
                           # genuinely single-field event types (e.g. done).
                           # Do NOT use f1/f2 for single-field events: both
                           # are lossy the moment the text itself contains a
                           # "|" (BUG FOUND IN SPIKE, see below).

  local has_arg2=false
  [[ "$payload" == *"|"* ]] && has_arg2=true

  local f1="${payload%%|*}"
  local f2=""
  $has_arg2 && f2="${payload#*|}"
  # f1/f2 are correct ONLY for genuinely-two-field events (status|text,
  # tier|text, band|score) where f2 is "everything after the first |" and
  # may itself safely contain more "|" characters (verified: step|ok|text
  # with embedded pipes renders intact). For single-field events, f1
  # truncates at the first embedded "|" and f2 additionally drops
  # everything up to and including that same "|" — neither equals the
  # original text once it contains a pipe. Originally this file assumed
  # "f1 == f2 == text" for single-field events; that's only true when the
  # text has zero embedded "|" characters. Use $rest for those instead.

  case "$evtype" in

    phase)
      # Arity guard: requires both agent (f1) and tier (f2). A malformed
      # phase line is dropped before any state mutation (no finalize, no
      # header print) so it never disturbs the active-spinner/line state.
      $has_arg2 || return 0
      # f1=agent  f2=tier
      [ -n "$ACTIVE_TEXT" ] && finalize_active ok
      local tc
      tc=$(tier_color "$f2")
      printf "\n${BOLD}${MAGENTA}▸${NC} ${BOLD}%s${NC} · ${tc}${BOLD}%s${NC}\n" \
        "$f1" "$f2"
      # No free-text field on phase — agent/tier (f1/f2) are display-only;
      # the milestone's agent/tier come from the env-injected identity above.
      record_milestone phase "" "" "" ""
      ;;

    step)
      # Arity guard: requires both status (f1) and text (f2) — a "step"
      # with no text field (e.g. "@@ANW|step|run") is dropped rather than
      # rendering the status keyword itself as the milestone text.
      $has_arg2 || return 0
      # f1=status(run|ok|fail)  f2=text
      local status="$f1"
      local text="$f2"
      case "$status" in
        run)
          [ -n "$ACTIVE_TEXT" ] && finalize_active ok
          ACTIVE_TEXT="$text"
          ACTIVE_START=$(date +%s)
          SPINNER_IDX=0
          # render_active will be called by the main loop after event processing
          record_milestone step run "$text" "" ""
          ;;
        ok)
          local display="${text:-$ACTIVE_TEXT}"
          if [ -n "$ACTIVE_TEXT" ]; then
            finalize_active ok "$display"
          else
            printf "  ${GREEN}⏺${NC} %s\n" "$display"
          fi
          record_milestone step ok "$display" "" ""
          ;;
        fail)
          local display="${text:-$ACTIVE_TEXT}"
          if [ -n "$ACTIVE_TEXT" ]; then
            finalize_active fail "$display"
          else
            printf "  ${RED}✗${NC} %s\n" "$display"
          fi
          record_milestone step fail "$display" "" ""
          ;;
        *)
          # Arity/vocab guard: status outside run|ok|fail is dropped.
          return 0
          ;;
      esac
      ;;

    deleg)
      # Arity guard: requires both sidekick tier (f1) and text (f2). A
      # malformed deleg line is dropped before finalize_active so it never
      # disturbs the active-spinner/line state.
      $has_arg2 || return 0
      # f1=sidekick_tier  f2=sidekick action description
      # Capture the parent's text BEFORE finalize_active clears ACTIVE_TEXT —
      # deleg_reject (below) does not touch ACTIVE_TEXT and reuses this same
      # tracked value, per the state-var note where it's declared.
      DELEG_PARENT_TEXT="$ACTIVE_TEXT"
      # Finalise the active step as [DELEGATED], then print the nested ↳ line.
      if [ -n "$ACTIVE_TEXT" ]; then
        finalize_active delegated
      fi
      printf "      ${DIM}↳ sidekick · %s:${NC} %s\n" "$f1" "$f2"
      record_milestone deleg "" "$f2" "$f1" "$DELEG_PARENT_TEXT"
      ;;

    deleg_reject)
      # Arity guard: requires both sidekick tier (f1) and reason (f2).
      $has_arg2 || return 0
      # f1=sidekick_tier  f2=rejection reason
      # Print rejection line. No state change — ACTIVE step is unchanged.
      printf "      ${RED}❌ sidekick · %s:${NC} %s\n" "$f1" "$f2"
      record_milestone deleg_reject "" "$f2" "$f1" "$DELEG_PARENT_TEXT"
      ;;

    verdict)
      # Arity guard: requires both band (f1) and score (f2).
      $has_arg2 || return 0
      # f1=band(GREEN|YELLOW|RED)  f2=score
      local vc band_upper
      band_upper=$(printf '%s' "$f1" | tr '[:lower:]' '[:upper:]')
      case "$band_upper" in
        GREEN)  vc="$GREEN"  ;;
        YELLOW) vc="$YELLOW" ;;
        RED)    vc="$RED"    ;;
        *)      vc="$NC"     ;;
      esac
      printf "  ${DIM}verdict:${NC} ${vc}${BOLD}%s${NC} ${DIM}(%s)${NC}\n" \
        "$f1" "$f2"
      # No OQ-2 column for band/score individually — record the rendered
      # "<band> (<score>)" form as text so nothing is lost.
      record_milestone verdict "" "$f1 ($f2)" "" ""
      ;;

    done)
      # Arity guard: requires the single free-text field (has_arg). Without
      # it, "${payload#*|}" would leave $rest unchanged at the evtype's own
      # trailing remainder — dropping avoids echoing "done" back as if it
      # were the summary text.
      $has_arg || return 0
      # Single-field event: summary text is everything after "done|".
      # Use $rest (the raw post-evtype remainder), not f1/f2 — see note
      # above main parse block. f1/f2 truncate/drop content the moment
      # this text contains an embedded "|" character.
      [ -n "$ACTIVE_TEXT" ] && finalize_active ok
      printf "\n${GREEN}✓${NC} ${BOLD}%s${NC}\n\n" "$rest"
      record_milestone done "" "$rest" "" ""
      ;;

    *)
      # SDK-1 B-2: unknown event type — dropped (never crashes; the case
      # falls through cleanly under set -euo pipefail).
      return 0
      ;;

  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {

  if ! $IS_TTY; then
    # ── Plain / non-TTY path ─────────────────────────────────────────────────
    # Simple blocking read; no spinner, no carriage-return tricks.
    while IFS= read -r line || [ -n "$line" ]; do
      handle_event "$line"
    done
    return
  fi

  # ── TTY path: FIFO-based event queue ─────────────────────────────────────
  #
  # Design constraints:
  #   - macOS ships bash 3.2; fractional read -t (e.g. -t 0.2) is unsupported.
  #   - Integer read -t works in bash 3.2 (e.g. -t 5).
  #
  # Solution: a background TICKER process writes an in-band heartbeat sentinel
  # (@@ANW|__TICK__) to the same FIFO every 0.2 s.  The main loop uses a
  # safe integer read -t 5 (only fires if ticker dies unexpectedly).  Both
  # real events and ticks arrive on fd 3; the case statement routes them.
  #
  # The FIFO is opened read+write (exec 3<>) so the write-end stays open in
  # this process.  Feeder and ticker inherit fd 3 and write through it.
  # An in-band @@ANW|__EOF__ sentinel signals true end of stream.
  local FIFO
  FIFO=$(mktemp -u "${TMPDIR:-/tmp}/anw-render-XXXXXX")
  mkfifo "$FIFO"
  exec 3<>"$FIFO"
  rm -f "$FIFO"   # unlink name; fd 3 keeps the inode alive

  # IMPORTANT: bash redirects stdin of background jobs (&) to /dev/null in
  # non-interactive shells.  Save stdin to fd 4 first, then explicitly read
  # from <&4 inside the feeder so it can still drain the input pipe.
  exec 4<&0

  # Feeder: drain stdin (fd 4) into the FIFO, then write EOF sentinel
  (cat <&4; printf '@@ANW|__EOF__\n') >&3 &
  local FEEDER_PID=$!

  exec 4<&-   # close fd 4 in the main process; feeder's copy remains open

  # Ticker: write heartbeat every 0.2 s so the main loop can animate spinner
  (while true; do sleep 0.2; printf '@@ANW|__TICK__\n' >&3 || break; done) &
  local TICKER_PID=$!

  # Hide cursor while animating
  printf '\033[?25l'

  # Cleanup on unexpected exit (ctrl-C, error, etc.)
  local _ap="$FEEDER_PID" _tp="$TICKER_PID"
  # shellcheck disable=SC2064
  trap "printf '\033[?25h'
        [ -n \"\${ACTIVE_TEXT:-}\" ] && finalize_active ok 2>/dev/null || true
        kill '$_tp' 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        exec 4<&- 2>/dev/null || true
        wait '$_ap' 2>/dev/null || true" EXIT

  local line=""
  while true; do
    line=""
    # Integer timeout (bash 3.2 compatible); ticker makes 5 s rarely trigger
    IFS= read -r -t 5 -u 3 line || true
    case "$line" in
      "@@ANW|__TICK__")
        render_active
        ;;
      "@@ANW|__EOF__")
        break
        ;;
      *)
        clear_line
        handle_event "$line"
        render_active
        ;;
    esac
  done

  # Normal exit — finalise, restore cursor, teardown
  [ -n "$ACTIVE_TEXT" ] && finalize_active ok
  printf '\033[?25h'

  kill "$TICKER_PID" 2>/dev/null || true
  exec 3>&-
  exec 4<&- 2>/dev/null || true
  wait "$FEEDER_PID" 2>/dev/null || true

  trap - EXIT
}

main
