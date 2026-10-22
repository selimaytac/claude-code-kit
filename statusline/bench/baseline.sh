#!/bin/bash
# Status line: context window usage with the growth of the last turns, e.g.
#   ☀ Clear 36% of context 367k / 1M · last turns ▁▂█▃ ▲ +12.4k last turn · $29.94 · left 5h 69% 7d 80%
# The same status line written the common way, as the baseline for bench.py.
# Readings per session are kept in ~/.claude/statusline-state/<session id> (last 9 values).
input=$(cat)

read -r session used size cost five seven < <(echo "$input" | jq -r '
  .context_window as $c
  | ($c.current_usage) as $u
  | (if $u then (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0))
     else ($c.total_input_tokens // 0) end) as $t
  | "\(.session_id // "default") \($t) \($c.context_window_size // 0) \(.cost.total_cost_usd // "-")"
    + " \(.rate_limits.five_hour.used_percentage // "-") \(.rate_limits.seven_day.used_percentage // "-")"' 2>/dev/null)
[ -z "$size" ] || [ "$size" = "0" ] && exit 0

# Keep one reading per turn: append only when the figure changed. Shell builtins only, since this runs on every
# refresh of every session.
state_dir="$HOME/.claude/statusline-state"
state="$state_dir/${session//[^A-Za-z0-9_-]/_}"
if [ ! -f "$state" ]; then
  [ -d "$state_dir" ] || mkdir -p "$state_dir"
  # A new session: drop state files of sessions idle for more than a week.
  find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
fi
printf '%s' "$size" > "$state.size"
readings=() last=
[ -f "$state" ] && while read -r line; do readings+=("$line"); last=$line; done < "$state"
if [ "$used" != "0" ] && [ "$used" != "$last" ]; then
  readings+=("$used")
  [ ${#readings[@]} -gt 9 ] && readings=("${readings[@]: -9}")
  printf '%s\n' "${readings[@]}" > "$state"
fi

awk -v used="$used" -v size="$size" -v readings="${readings[*]}" -v cost="$cost" -v five="$five" -v seven="$seven" '
# What is left of a rate-limit window, colored once it runs low.
function limit(name, used) {
  left = 100 - used; if (left < 0) left = 0
  if (left <= 10) c = esc "[31m"; else if (left <= 25) c = esc "[38;5;208m"; else c = dim
  return c name " " int(left + 0.5) "%" reset
}
function fmt(n) {
  if (n >= 1000000) return sprintf("%gM", int(n / 100000 + 0.5) / 10)
  if (n >= 100000) return sprintf("%dk", int(n / 1000 + 0.5))
  if (n >= 1000) return sprintf("%gk", int(n / 100 + 0.5) / 10)
  return n
}
BEGIN {
  esc = sprintf("%c", 27); reset = esc "[0m"; dim = esc "[2m"; bold = esc "[1m"
  pct = int(used * 100 / size)
  if (pct >= 85)      { color = esc "[31m"; icon = "●"; label = "Full" }
  else if (pct >= 70) { color = esc "[38;5;208m"; icon = "▲"; label = "Tight" }
  else if (pct >= 50) { color = esc "[33m"; icon = "◐"; label = "Filling" }
  else                { color = esc "[33m"; icon = "☀"; label = "Clear" }

  line = color icon " " bold label reset " " pct "% of context " dim fmt(used) " / " fmt(size) reset

  # Growth per turn: the differences between consecutive readings (a drop, as after /compact, counts as 0).
  n = split(readings, r, " ")
  m = 0; max = 0
  for (i = 2; i <= n; i++) { d = r[i] - r[i - 1]; if (d < 0) d = 0; g[++m] = d; if (d > max) max = d }
  if (m > 0) {
    split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", bars, " ")
    spark = ""
    for (i = 1; i <= m; i++) spark = spark (max > 0 ? bars[int(g[i] * 7 / max) + 1] : bars[1])
    line = line dim " · last turns " reset color spark reset
    delta = r[n] - r[n - 1]
    if (delta >= 0) line = line dim " ▲ +" fmt(delta) " last turn" reset
    else line = line dim " ▼ -" fmt(-delta) " last turn" reset
  }

  # Session cost, and the subscription limits when the last response reported them.
  if (cost != "-") line = line dim " · " sprintf("$%.2f", cost) reset
  if (five != "-" || seven != "-") {
    line = line dim " · left" reset
    if (five != "-") line = line " " limit("5h", five)
    if (seven != "-") line = line " " limit("7d", seven)
  }
  print line
}'
