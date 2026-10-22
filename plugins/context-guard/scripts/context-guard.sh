#!/bin/sh
# UserPromptSubmit hook: tells the agent once when the context window passes WARN% and once when it passes STOP%,
# so it wraps up and leaves a summary before the window fills or auto-compact kicks in. Silent otherwise.
# Context in use = input + cache tokens of the last main-thread assistant message in the session transcript.
# Settings (environment): CONTEXT_GUARD_WINDOW (tokens, default 200000; set 1000000 for 1M-context models),
# CONTEXT_GUARD_WARN (default 70), CONTEXT_GUARD_STOP (default 85).
input=$(cat)
field() { printf '%s' "$input" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1; }
transcript=$(field transcript_path); session=$(field session_id)
[ -f "$transcript" ] || exit 0
window=${CONTEXT_GUARD_WINDOW:-200000}; warn=${CONTEXT_GUARD_WARN:-70}; stop=${CONTEXT_GUARD_STOP:-85}

used=$(tail -n 400 "$transcript" | grep '"usage"' | grep -v '"isSidechain":true' | tail -n 1 | awk '{
  n = split("input_tokens cache_creation_input_tokens cache_read_input_tokens", f, " "); s = 0
  for (i = 1; i <= n; i++) if (match($0, "\"" f[i] "\": *[0-9]+")) { v = substr($0, RSTART, RLENGTH); sub(/.*: */, "", v); s += v }
  print s }')
[ -n "$used" ] && [ "$window" -gt 0 ] 2>/dev/null || exit 0
pct=$(( used * 100 / window ))
level=0; [ "$pct" -ge "$warn" ] && level=1; [ "$pct" -ge "$stop" ] && level=2
[ "$level" -eq 0 ] && exit 0

# Warn once per level per session.
mark="${TMPDIR:-/tmp}/context-guard-$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')"
prev=$(cat "$mark" 2>/dev/null || echo 0)
[ "$level" -le "$prev" ] && exit 0
echo "$level" > "$mark"

if [ "$level" -eq 2 ]; then
  msg="Context is at ${pct}% of the window. Do not start new work. Write a short summary of what is done, what is left and the next step, then ask the user to run /compact or start a fresh session from that summary."
else
  msg="Context is at ${pct}% of the window. Finish the current step only, then write a short summary of progress and next steps, and ask the user whether to continue here or start fresh."
fi
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg"
