#!/bin/bash
#
# Tests for cc-statusline.
#
# Usage: ./tests.sh
# Exit code 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/statusline.sh"

PASSED=0
FAILED=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────────────────────

# Strip ANSI escape sequences from text
strip_ansi() {
    sed $'s/\033\\[[0-9;]*m//g'
}

# Run the statusline script with given JSON input and optional env vars.
# Usage: run_statusline '{"json": ...}' [ENV_VAR=value ...]
run_statusline() {
    local json="$1"
    shift
    env "$@" bash "$SCRIPT" <<< "$json" 2>/dev/null
}

# Assert that output contains a string (after stripping ANSI codes).
assert_contains() {
    local test_name="$1" output="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | strip_ansi | grep -qF -- "$expected"; then
        PASSED=$((PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$test_name"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[31m✗\033[0m %s (expected to find: %s)\n' "$test_name" "$expected"
    fi
}

# Assert that output does NOT contain a string (after stripping ANSI codes).
assert_not_contains() {
    local test_name="$1" output="$2" unexpected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | strip_ansi | grep -qF -- "$unexpected"; then
        FAILED=$((FAILED + 1))
        printf '  \033[31m✗\033[0m %s (unexpectedly found: %s)\n' "$test_name" "$unexpected"
    else
        PASSED=$((PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$test_name"
    fi
}

# Assert exact string equality.
assert_eq() {
    local test_name="$1" actual="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASSED=$((PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$test_name"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[31m✗\033[0m %s (expected: "%s", got: "%s")\n' "$test_name" "$expected" "$actual"
    fi
}

# Assert line count. Uses printf to avoid echo adding a trailing newline
# that would inflate the count for empty/whitespace-only output.
assert_line_count() {
    local test_name="$1" output="$2" expected="$3"
    local actual
    actual=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -eq "$expected" ]; then
        PASSED=$((PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$test_name"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[31m✗\033[0m %s (expected %d lines, got %d)\n' "$test_name" "$expected" "$actual"
    fi
}

# ── Test JSON payloads ───────────────────────────────────────────────────

FULL_JSON='{
    "model": {"display_name": "Opus 4.6 (1M context)"},
    "workspace": {"current_dir": "/tmp/test-project"},
    "context_window": {
        "used_percentage": 42.7,
        "remaining_percentage": 57.3,
        "total_input_tokens": 125000,
        "total_output_tokens": 45000
    },
    "cost": {
        "total_cost_usd": 1.2345,
        "total_lines_added": 150,
        "total_lines_removed": 30,
        "total_duration_ms": 5400000
    },
    "rate_limits": {
        "five_hour": {"used_percentage": 55, "resets_at": 0},
        "seven_day": {"used_percentage": 60, "resets_at": 0}
    },
    "worktree": {"name": "feature-x"}
}'

EMPTY_JSON='{}'

MINIMAL_JSON='{"model": {"display_name": "Sonnet 4.5"}}'

# ── Test: Helper functions ───────────────────────────────────────────────

echo "Helper functions:"

# Source only the functions we need (run in a subshell to avoid polluting state).
# We pipe empty JSON so the jq/read at the top doesn't block.
_test_helper() {
    # Source the script to get function definitions, suppressing output
    (
        eval "$(grep -A 100 '^make_bar()' "$SCRIPT" | head -11)"
        eval "$(grep -A 100 '^format_duration()' "$SCRIPT" | head -12)"
        eval "$(grep -A 100 '^fmt_tokens()' "$SCRIPT" | head -17)"

        # make_bar tests
        printf 'make_bar:%s\n' "$(make_bar 0 10)"
        printf 'make_bar:%s\n' "$(make_bar 100 10)"
        printf 'make_bar:%s\n' "$(make_bar 50 10)"
        printf 'make_bar:%s\n' "$(make_bar 0 4)"

        # format_duration tests
        printf 'duration:%s\n' "$(format_duration 0)"
        printf 'duration:%s\n' "$(format_duration 3600000)"
        printf 'duration:%s\n' "$(format_duration 5400000)"
        printf 'duration:%s\n' "$(format_duration 120000)"

        # fmt_tokens tests
        printf 'tokens:%s\n' "$(fmt_tokens 500)"
        printf 'tokens:%s\n' "$(fmt_tokens 1500)"
        printf 'tokens:%s\n' "$(fmt_tokens 1500000)"
        printf 'tokens:%s\n' "$(fmt_tokens 0)"
    )
}

HELPER_OUT=$(_test_helper)

assert_eq "make_bar 0% 10-wide = all empty"     "$(echo "$HELPER_OUT" | sed -n '1s/^make_bar://p')" "░░░░░░░░░░"
assert_eq "make_bar 100% 10-wide = all filled"   "$(echo "$HELPER_OUT" | sed -n '2s/^make_bar://p')" "██████████"
assert_eq "make_bar 50% 10-wide = half/half"     "$(echo "$HELPER_OUT" | sed -n '3s/^make_bar://p')" "█████░░░░░"
assert_eq "make_bar 0% 4-wide = all empty"       "$(echo "$HELPER_OUT" | sed -n '4s/^make_bar://p')" "░░░░"

assert_eq "format_duration 0ms = 0m"             "$(echo "$HELPER_OUT" | sed -n '5s/^duration://p')" "0m"
assert_eq "format_duration 3600000ms = 1h0m"     "$(echo "$HELPER_OUT" | sed -n '6s/^duration://p')" "1h0m"
assert_eq "format_duration 5400000ms = 1h30m"    "$(echo "$HELPER_OUT" | sed -n '7s/^duration://p')" "1h30m"
assert_eq "format_duration 120000ms = 2m"        "$(echo "$HELPER_OUT" | sed -n '8s/^duration://p')" "2m"

assert_eq "fmt_tokens 500 = 500"                 "$(echo "$HELPER_OUT" | sed -n '9s/^tokens://p')"  "500"
assert_eq "fmt_tokens 1500 = 1.5k"               "$(echo "$HELPER_OUT" | sed -n '10s/^tokens://p')" "1.5k"
assert_eq "fmt_tokens 1500000 = 1.5M"            "$(echo "$HELPER_OUT" | sed -n '11s/^tokens://p')" "1.5M"
assert_eq "fmt_tokens 0 = 0"                     "$(echo "$HELPER_OUT" | sed -n '12s/^tokens://p')" "0"

# ── Test: Output structure ───────────────────────────────────────────────

echo ""
echo "Output structure:"

OUT_FULL=$(run_statusline "$FULL_JSON" CS_HIDE_GIT=1)
assert_line_count "full input produces 2 lines" "$OUT_FULL" 2

LINE1=$(echo "$OUT_FULL" | head -1)
LINE2=$(echo "$OUT_FULL" | tail -1)
assert_contains "line 1 is non-empty" "$LINE1" "Opus"
# Line 2 should have tokens or rate limit info
assert_contains "line 2 has token info" "$LINE2" "in/"

# ── Test: Default content ────────────────────────────────────────────────

echo ""
echo "Default content (all sections visible):"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_GIT=1)
assert_contains "shows model name"          "$OUT" "Opus 4.6"
assert_contains "shows context percentage"  "$OUT" "42%"
assert_contains "shows directory"           "$OUT" "/tmp/test-project"
assert_contains "shows worktree"            "$OUT" "wt:feature-x"
assert_contains "shows lines added"         "$OUT" "+150"
assert_contains "shows lines removed"       "$OUT" "-30"
assert_contains "shows cost"                "$OUT" '$1.23'
assert_contains "shows duration"            "$OUT" "1h30m"
assert_contains "shows 5h rate limit"       "$OUT" "5h"
assert_contains "shows 7d rate limit"       "$OUT" "7d"
assert_contains "shows tokens"              "$OUT" "in/"

# ── Test: Visibility toggles ────────────────────────────────────────────

echo ""
echo "Visibility toggles:"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_MODEL=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_MODEL hides model"      "$OUT" "Opus"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_CONTEXT=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_CONTEXT hides context"   "$OUT" "Context:"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_DIR=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_DIR hides directory"     "$OUT" "/tmp/test-project"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_LINES=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_LINES hides +added"      "$OUT" "+150"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_5H_USAGE=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_5H_USAGE hides 5h"       "$OUT" "5h"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_7D_USAGE=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_7D_USAGE hides 7d"       "$OUT" "7d"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_TOKENS=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_TOKENS hides tokens"     "$OUT" "in/"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_WORKTREE=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_WORKTREE hides worktree" "$OUT" "wt:"

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_COST=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_COST hides cost"         "$OUT" '$1.23'

OUT=$(run_statusline "$FULL_JSON" CS_HIDE_DURATION=1 CS_HIDE_GIT=1)
assert_not_contains "CS_HIDE_DURATION hides duration"  "$OUT" "1h30m"

# Hide everything — should not crash
TOTAL=$((TOTAL + 1))
if run_statusline "$FULL_JSON" \
    CS_HIDE_MODEL=1 CS_HIDE_CONTEXT=1 CS_HIDE_DIR=1 CS_HIDE_GIT=1 \
    CS_HIDE_LINES=1 CS_HIDE_5H_USAGE=1 CS_HIDE_7D_USAGE=1 \
    CS_HIDE_TOKENS=1 CS_HIDE_WORKTREE=1 CS_HIDE_COST=1 CS_HIDE_DURATION=1 > /dev/null 2>&1; then
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m hide all: does not crash\n'
else
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m hide all: does not crash\n'
fi

# ── Test: Tuning variables ───────────────────────────────────────────────

echo ""
echo "Tuning variables:"

# Wider context bar
OUT_WIDE=$(run_statusline "$FULL_JSON" CS_CTX_BAR_WIDTH=8 CS_HIDE_GIT=1)
OUT_DEFAULT=$(run_statusline "$FULL_JSON" CS_HIDE_GIT=1)
WIDE_BAR_LEN=$(echo "$OUT_WIDE" | strip_ansi | head -1 | grep -o '[█░]*' | head -1 | wc -c | tr -d ' ')
DEFAULT_BAR_LEN=$(echo "$OUT_DEFAULT" | strip_ansi | head -1 | grep -o '[█░]*' | head -1 | wc -c | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [ "$WIDE_BAR_LEN" -gt "$DEFAULT_BAR_LEN" ]; then
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m CS_CTX_BAR_WIDTH=8 produces wider bar\n'
else
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m CS_CTX_BAR_WIDTH=8 produces wider bar (wide=%d, default=%d)\n' "$WIDE_BAR_LEN" "$DEFAULT_BAR_LEN"
fi

# 7d show threshold — hide 7d when below threshold
OUT=$(run_statusline "$FULL_JSON" CS_RL_7D_SHOW_PCT=100 CS_HIDE_GIT=1)
assert_not_contains "CS_RL_7D_SHOW_PCT=100 hides 7d at 60%" "$OUT" "7d"

# ── Test: Edge cases ────────────────────────────────────────────────────

echo ""
echo "Edge cases:"

OUT=$(run_statusline "$EMPTY_JSON" CS_HIDE_GIT=1)
assert_line_count "empty JSON produces 2 lines"       "$OUT" 2
assert_contains   "empty JSON shows unknown model"     "$OUT" "unknown"

OUT=$(run_statusline "$MINIMAL_JSON" CS_HIDE_GIT=1)
assert_line_count "minimal JSON produces 2 lines"     "$OUT" 2
assert_contains   "minimal JSON shows model"           "$OUT" "Sonnet 4.5"

# Worktree with numeric name should be hidden
NUMERIC_WT_JSON='{"worktree": {"name": "12345"}}'
OUT=$(run_statusline "$NUMERIC_WT_JSON" CS_HIDE_GIT=1)
assert_not_contains "numeric worktree name is hidden"  "$OUT" "wt:12345"

# Non-git directory — CS_HIDE_GIT is not set, but /tmp is not a git repo
OUT=$(run_statusline '{"workspace": {"current_dir": "/tmp"}}')
assert_line_count "non-git dir produces 2 lines"       "$OUT" 2

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
if [ "$FAILED" -eq 0 ]; then
    printf '\033[32m%d/%d tests passed\033[0m\n' "$PASSED" "$TOTAL"
    exit 0
else
    printf '\033[31m%d/%d tests passed (%d failed)\033[0m\n' "$PASSED" "$TOTAL" "$FAILED"
    exit 1
fi
