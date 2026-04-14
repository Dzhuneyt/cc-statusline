#!/bin/bash
#
# cc-statusline — a two-line ANSI statusline for Claude Code.
#
# Claude Code invokes this script on every render cycle, pipes a JSON blob
# on stdin, and displays whatever goes to stdout as the statusline.
#
# ── Input ────────────────────────────────────────────────────────────────
# Single JSON object on stdin. All fields are optional:
#   .model.display_name
#   .workspace.current_dir              (falls back to .cwd)
#   .context_window.used_percentage
#   .context_window.remaining_percentage
#   .context_window.total_input_tokens
#   .context_window.total_output_tokens
#   .cost.total_cost_usd
#   .cost.total_lines_added
#   .cost.total_lines_removed
#   .cost.total_duration_ms
#   .rate_limits.five_hour.{used_percentage, resets_at}
#   .rate_limits.seven_day.{used_percentage, resets_at}
#   .worktree.name
#
# ── Output ───────────────────────────────────────────────────────────────
# Two lines with ANSI color escapes:
#   line 1: model | context bar | cwd [| wt:name] [| git status] | lines
#   line 2: [5h rate limit] [| 7d rate limit] | tokens
#
# ── Configuration ────────────────────────────────────────────────────────
# All behavior is controlled via environment variables. Everything is
# shown by default. Set any CS_HIDE_* variable to a non-empty value to
# hide that section.
#
# Visibility toggles:
#   CS_HIDE_MODEL       Hide model name
#   CS_HIDE_CONTEXT     Hide context window bar
#   CS_HIDE_DIR         Hide working directory
#   CS_HIDE_GIT         Hide git branch and diff stats
#   CS_HIDE_LINES       Hide session lines added/removed
#   CS_HIDE_5H_USAGE    Hide 5-hour rate limit
#   CS_HIDE_7D_USAGE    Hide 7-day rate limit
#   CS_HIDE_TOKENS      Hide token counts
#   CS_HIDE_WORKTREE    Hide worktree indicator
#   CS_HIDE_COST        Hide session cost
#   CS_HIDE_DURATION    Hide session duration
#
# Tuning (defaults in parentheses):
#   CS_CTX_BAR_WIDTH    Context bar width in chars (4)
#   CS_RL_BAR_WIDTH     Rate limit bar width in chars (4)
#   CS_CTX_WARN_PCT     Context % where color turns yellow (50)
#   CS_CTX_CRIT_PCT     Context % where color turns red (75)
#   CS_RL_WARN_PCT      Rate limit % where color turns yellow (70)
#   CS_RL_CRIT_PCT      Rate limit % where color turns red (90)
#   CS_RL_7D_SHOW_PCT   Show 7d limit only above this % (40)
#   CS_GIT_CACHE_TTL    Git status cache TTL in seconds (5)
#   CS_CACHE_DIR        Directory for git cache files (/tmp)
#
# ── Implementation notes ─────────────────────────────────────────────────
#   - The jq call uses \u001f (unit separator) rather than tabs because
#     bash `read` treats whitespace IFS chars specially and squashes
#     consecutive delimiters — an empty optional field would shift every
#     subsequent variable by one and silently corrupt the output.
#   - Git status is cached per-cwd to avoid thrashing across concurrent
#     sessions in different repos.

# ── Tuning defaults ─────────────────────────────────────────────────────
CS_CTX_BAR_WIDTH="${CS_CTX_BAR_WIDTH:-10}"
CS_RL_BAR_WIDTH="${CS_RL_BAR_WIDTH:-4}"
CS_CTX_WARN_PCT="${CS_CTX_WARN_PCT:-50}"
CS_CTX_CRIT_PCT="${CS_CTX_CRIT_PCT:-75}"
CS_RL_WARN_PCT="${CS_RL_WARN_PCT:-70}"
CS_RL_CRIT_PCT="${CS_RL_CRIT_PCT:-90}"
CS_RL_7D_SHOW_PCT="${CS_RL_7D_SHOW_PCT:-40}"
CS_GIT_CACHE_TTL="${CS_GIT_CACHE_TTL:-5}"
CS_CACHE_DIR="${CS_CACHE_DIR:-/tmp}"

# ── Parse all JSON fields in a single jq call ────────────────────────────
IFS=$'\x1f' read -r MODEL_NAME_RAW CWD CTX_PERCENT CTX_REMAINING_PCT COST LINES_ADDED LINES_REMOVED \
    DURATION_MS RL_5H_PCT RL_5H_RESET RL_7D_PCT RL_7D_RESET \
    WORKTREE_NAME TOTAL_IN TOTAL_OUT < <(
    jq -r '[
        (.model.display_name // "unknown"),
        (.workspace.current_dir // .cwd // ""),
        ((.context_window.used_percentage // 0) | floor | tostring),
        ((.context_window.remaining_percentage // 100) | floor | tostring),
        (.cost.total_cost_usd // 0 | . * 100 | round | . / 100 | tostring),
        (.cost.total_lines_added // 0 | tostring),
        (.cost.total_lines_removed // 0 | tostring),
        (.cost.total_duration_ms // 0 | tostring),
        ((.rate_limits.five_hour.used_percentage // 0) | floor | tostring),
        (.rate_limits.five_hour.resets_at // 0 | tostring),
        ((.rate_limits.seven_day.used_percentage // 0) | floor | tostring),
        (.rate_limits.seven_day.resets_at // 0 | tostring),
        (.worktree.name // ""),
        (.context_window.total_input_tokens // 0 | tostring),
        (.context_window.total_output_tokens // 0 | tostring)
    ] | join("\u001f")'
)

# ── Derived values ────────────────────────────────────────────────────────
DIR="${CWD/#$HOME/~}"
CTX_PERCENT="${CTX_PERCENT:-0}"
CTX_REMAINING="${CTX_REMAINING_PCT:-100}"
# Strip parenthetical suffix from display name (e.g. "Opus 4.6 (1M context)" → "Opus 4.6")
MODEL_NAME="${MODEL_NAME_RAW%% (*}"

# ── Colors ───────────────────────────────────────────────────────────────
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
SEP="\033[2m | \033[0m"

# ── Progress bar helper ──────────────────────────────────────────────────
make_bar() {
    local pct="${1:-0}" width="${2:-10}"
    local filled
    if [ "$pct" -gt 0 ]; then
        filled=$(( (pct * width + 99) / 100 ))
    else
        filled=0
    fi
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    [ "$filled" -gt 0 ] && bar=$(printf '█%.0s' $(seq 1 "$filled"))
    [ "$empty" -gt 0 ] && bar="${bar}$(printf '░%.0s' $(seq 1 "$empty"))"
    printf '%s' "$bar"
}

# ── Color by percentage helper ───────────────────────────────────────────
pct_color() {
    local pct="${1:-0}" warn="${2:-50}" crit="${3:-75}"
    if [ "$pct" -ge "$crit" ]; then printf '%b' "$RED"
    elif [ "$pct" -ge "$warn" ]; then printf '%b' "$YELLOW"
    else printf '%b' "$GREEN"
    fi
}

# ── Session duration ─────────────────────────────────────────────────────
format_duration() {
    local ms="${1:-0}"
    local total_secs=$(( ms / 1000 ))
    local hrs=$(( total_secs / 3600 ))
    local mins=$(( (total_secs % 3600) / 60 ))
    if [ "$hrs" -gt 0 ]; then
        printf '%dh%dm' "$hrs" "$mins"
    else
        printf '%dm' "$mins"
    fi
}

# ── Format token count (e.g. 1234 → 1.2k, 1234567 → 1.2M) ─────────────
fmt_tokens() {
    local n="${1:-0}"
    local whole tenths
    if [ "$n" -ge 1000000 ]; then
        whole=$(( n / 1000000 ))
        tenths=$(( (n % 1000000 + 50000) / 100000 ))
        [ "$tenths" -ge 10 ] && { whole=$((whole+1)); tenths=0; }
        printf '%s.%sM' "$whole" "$tenths"
    elif [ "$n" -ge 1000 ]; then
        whole=$(( n / 1000 ))
        tenths=$(( (n % 1000 + 50) / 100 ))
        [ "$tenths" -ge 10 ] && { whole=$((whole+1)); tenths=0; }
        printf '%s.%sk' "$whole" "$tenths"
    else
        printf '%s' "$n"
    fi
}

# ── Rate limit remaining-time helper ─────────────────────────────────────
fmt_remaining() {
    local target="${1:-0}"
    [ "$target" -le 0 ] && return
    local now_ts=$(date +%s)
    local remaining=$(( target - now_ts ))
    [ "$remaining" -le 0 ] && return
    local rd=$(( remaining / 86400 ))
    local rh=$(( (remaining % 86400) / 3600 ))
    local rm=$(( (remaining % 3600) / 60 ))
    if [ "$rd" -gt 0 ]; then
        printf ' %dd %dh' "$rd" "$rh"
    elif [ "$rh" -gt 0 ]; then
        printf ' %dh %dm' "$rh" "$rm"
    else
        printf ' %dm' "$rm"
    fi
}

# ── Computed displays ────────────────────────────────────────────────────
DURATION=$(format_duration "$DURATION_MS")
TOKENS_DISPLAY="$(fmt_tokens "$TOTAL_IN") in/$(fmt_tokens "$TOTAL_OUT") out"
COST_DISPLAY=$(printf '$%.2f' "$COST" 2>/dev/null || echo '$0.00')
LINES_DISPLAY="${GREEN}+${LINES_ADDED}${RESET} ${RED}-${LINES_REMOVED}${RESET} ${DIM}(session)${RESET}"

# ── Git status with cached TTL ───────────────────────────────────────────
GIT_CACHE="${CS_CACHE_DIR}/claude-statusline-git-$(echo "$CWD" | md5 2>/dev/null || echo "$CWD" | md5sum | cut -d' ' -f1)"
GIT_STATUS=""

if [ -z "$CS_HIDE_GIT" ] && git -C "${CWD:-.}" rev-parse --git-dir > /dev/null 2>&1; then
    now=$(date +%s)
    cache_valid=false

    if [ -f "$GIT_CACHE" ]; then
        cache_ts=$(head -1 "$GIT_CACHE" 2>/dev/null)
        if [ -n "$cache_ts" ] && [ "$((now - cache_ts))" -lt "$CS_GIT_CACHE_TTL" ]; then
            cache_valid=true
            GIT_STATUS=$(tail -n +2 "$GIT_CACHE")
        fi
    fi

    if [ "$cache_valid" = false ]; then
        branch=$(git -C "${CWD:-.}" --no-optional-locks branch --show-current 2>/dev/null)
        if [ -n "$branch" ]; then
            GIT_STATUS="$branch"

            staged_numstat=$(git -C "${CWD:-.}" --no-optional-locks diff --cached --numstat 2>/dev/null)
            unstaged_numstat=$(git -C "${CWD:-.}" --no-optional-locks diff --numstat 2>/dev/null)

            staged_added=$(echo "$staged_numstat" | awk '{sum += $1} END {print sum+0}')
            staged_removed=$(echo "$staged_numstat" | awk '{sum += $2} END {print sum+0}')
            unstaged_added=$(echo "$unstaged_numstat" | awk '{sum += $1} END {print sum+0}')
            unstaged_removed=$(echo "$unstaged_numstat" | awk '{sum += $2} END {print sum+0}')
            untracked=$(git -C "${CWD:-.}" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

            changes=""

            if [ "$staged_added" -gt 0 ] || [ "$staged_removed" -gt 0 ]; then
                changes="${changes} ${GREEN}+${staged_added} -${staged_removed}${RESET}"
            fi

            if [ "$unstaged_added" -gt 0 ] || [ "$unstaged_removed" -gt 0 ]; then
                changes="${changes} ${YELLOW}+${unstaged_added} -${unstaged_removed}${RESET}"
            fi

            if [ "$untracked" -gt 0 ]; then
                changes="${changes} ${DIM}?${untracked}${RESET}"
            fi

            if [ -n "$changes" ]; then
                GIT_STATUS="${GIT_STATUS}${changes} ${DIM}(git)${RESET}"
            else
                GIT_STATUS="${GIT_STATUS} ${GREEN}clean${RESET} ${DIM}(git)${RESET}"
            fi
        fi

        printf '%s\n%s\n' "$now" "$GIT_STATUS" > "$GIT_CACHE"
    fi
fi

# ── Rate limit display ──────────────────────────────────────────────────
DOT="${DIM} · ${RESET}"
RL_DISPLAY=""
if [ -z "$CS_HIDE_5H_USAGE" ]; then
    if [ "${RL_5H_PCT:-0}" -gt 0 ] || [ "${RL_5H_RESET:-0}" -gt 0 ]; then
        RL_COLOR=$(pct_color "$RL_5H_PCT" "$CS_RL_WARN_PCT" "$CS_RL_CRIT_PCT")
        RL_BAR=$(make_bar "$RL_5H_PCT" "$CS_RL_BAR_WIDTH")
        RL_5H_REM=$(fmt_remaining "${RL_5H_RESET:-0}")
        RL_5H_SUFFIX=""
        [ -n "$RL_5H_REM" ] && RL_5H_SUFFIX=" (${RL_5H_REM# } till reset)"
        RL_DISPLAY="${DOT}${DIM}5h${RESET} ${RL_COLOR}${RL_BAR} ${RL_5H_PCT}%${RESET}${DIM}${RL_5H_SUFFIX}${RESET}"
    fi
fi
if [ -z "$CS_HIDE_7D_USAGE" ]; then
    if [ "${RL_7D_PCT:-0}" -ge "$CS_RL_7D_SHOW_PCT" ]; then
        RL7_COLOR=$(pct_color "$RL_7D_PCT" "$CS_RL_WARN_PCT" "$CS_RL_CRIT_PCT")
        RL7_BAR=$(make_bar "$RL_7D_PCT" "$CS_RL_BAR_WIDTH")
        RL_7D_REM=$(fmt_remaining "${RL_7D_RESET:-0}")
        RL_7D_SUFFIX=""
        [ -n "$RL_7D_REM" ] && RL_7D_SUFFIX=" (${RL_7D_REM# } till reset)"
        RL_DISPLAY="${RL_DISPLAY}${SEP}${DIM}7d${RESET} ${RL7_COLOR}${RL7_BAR} ${RL_7D_PCT}%${RESET}${DIM}${RL_7D_SUFFIX}${RESET}"
    fi
fi

# ── Worktree display ────────────────────────────────────────────────────
WORKTREE_DISPLAY=""
if [ -z "$CS_HIDE_WORKTREE" ] && [ -n "$WORKTREE_NAME" ] && ! [[ "$WORKTREE_NAME" =~ ^[0-9]+$ ]]; then
    WORKTREE_DISPLAY="${SEP}${BOLD}wt:${WORKTREE_NAME}${RESET}"
fi

# ── Assemble line 1 ─────────────────────────────────────────────────────
LINE1=""

# Appends a section to LINE1 with separator handling
_append() {
    if [ -n "$LINE1" ]; then
        LINE1="${LINE1}${SEP}${1}"
    else
        LINE1="${1}"
    fi
}

[ -z "$CS_HIDE_MODEL" ] && _append "${MODEL_NAME}"

if [ -z "$CS_HIDE_CONTEXT" ]; then
    CTX_REM_COLOR=$(pct_color "$CTX_PERCENT" "$CS_CTX_WARN_PCT" "$CS_CTX_CRIT_PCT")
    CTX_BAR=$(make_bar "$CTX_PERCENT" "$CS_CTX_BAR_WIDTH")
    _append "${DIM}Context:${RESET} ${CTX_REM_COLOR}${CTX_BAR} ${CTX_PERCENT}%${RESET}"
fi

[ -z "$CS_HIDE_DIR" ] && _append "${DIR}"

# Worktree attaches to directory (no extra separator if dir is also shown)
if [ -n "$WORKTREE_DISPLAY" ]; then
    LINE1="${LINE1}${WORKTREE_DISPLAY}"
fi

[ -z "$CS_HIDE_GIT" ] && [ -n "$GIT_STATUS" ] && _append "${GIT_STATUS}"
[ -z "$CS_HIDE_LINES" ] && _append "${LINES_DISPLAY}"
[ -z "$CS_HIDE_COST" ] && _append "${COST_DISPLAY}"
[ -z "$CS_HIDE_DURATION" ] && _append "${DURATION}"

# ── Assemble line 2 ─────────────────────────────────────────────────────
LINE2_PARTS=""

_append2() {
    if [ -n "$LINE2_PARTS" ]; then
        LINE2_PARTS="${LINE2_PARTS}${SEP}${1}"
    else
        LINE2_PARTS="${1}"
    fi
}

# Strip leading dot separator from RL_DISPLAY
RL_DISPLAY_TRIMMED="${RL_DISPLAY#"$DOT"}"
[ -n "$RL_DISPLAY_TRIMMED" ] && _append2 "${RL_DISPLAY_TRIMMED}"

if [ -z "$CS_HIDE_TOKENS" ]; then
    _append2 "${DIM}Tokens: ${TOKENS_DISPLAY}${RESET}"
fi

LINE2="${LINE2_PARTS}"

# ── Output ───────────────────────────────────────────────────────────────
printf '%b\n%b\n' "$LINE1" "$LINE2"
