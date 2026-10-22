#!/usr/bin/awk -f
# Claude Code status line in one awk process (no bash, no jq), e.g.
#   ☀ Clear 36% of context 367k / 1M · last turns ▁▂█▃ ▲ +12.4k last turn · $29.94 · cache 3m · left 5h 69% 7d 80%
# settings.json: "statusLine": {"type": "command", "command": "awk -f ~/.claude/statusline.awk", "refreshInterval": 30}
# Readings per session are kept in ~/.claude/statusline-state/<session id> (last 9 values, one per line) and the
# window size in <session id>.size.

# --- a small JSON reader: every scalar lands in J["a.b.c"] (array items as a.0, a.1, ...) ---
function jpath(   p, d) {
  p = ""
  for (d = 1; d <= depth; d++) p = p (d > 1 ? "." : "") (type[d] == "o" ? key[d] : idx[d])
  return p
}
function parse(s,   n, i, c, rest, v) {
  n = length(s); i = 1; depth = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "{") { type[++depth] = "o"; want[depth] = 1; i++ }
    else if (c == "[") { type[++depth] = "a"; idx[depth] = 0; i++ }
    else if (c == "}" || c == "]") { depth--; i++ }
    else if (c == ",") { if (type[depth] == "o") want[depth] = 1; else idx[depth]++; i++ }
    else if (c == "\"") {
      rest = substr(s, i + 1); match(rest, /^([^"\\]|\\.)*/); v = substr(rest, 1, RLENGTH); i += RLENGTH + 2
      if (type[depth] == "o" && want[depth]) { key[depth] = v; want[depth] = 0 } else J[jpath()] = v
    }
    else if (c ~ /[-0-9tfn]/) {
      rest = substr(s, i); match(rest, /^(-?[0-9.eE+-]+|true|false|null)/); v = substr(rest, 1, RLENGTH); i += RLENGTH
      if (RLENGTH <= 0) i++; else if (v != "null") J[jpath()] = v
    }
    else i++
  }
}
function get(k, fallback) { return (k in J) ? J[k] : fallback }

function fmt(n) {
  if (n >= 1000000) return sprintf("%gM", int(n / 100000 + 0.5) / 10)
  if (n >= 100000) return sprintf("%dk", int(n / 1000 + 0.5))
  if (n >= 1000) return sprintf("%gk", int(n / 100 + 0.5) / 10)
  return n
}
function dur(sec) {  # 75 -> 1m, 4000 -> 1h7m
  if (sec < 60) return int(sec) "s"
  if (sec < 3600) return int(sec / 60) "m"
  return int(sec / 3600) "h" (int(sec % 3600 / 60) ? int(sec % 3600 / 60) "m" : "")
}
# What is left of a rate-limit window, colored once it runs low; when low, also when it resets.
function limit(name, used, resets,   left, c, s) {
  left = 100 - used; if (left < 0) left = 0
  if (left <= 10) c = esc "[31m"; else if (left <= 25) c = esc "[38;5;208m"; else c = dim
  s = c name " " int(left + 0.5) "%"
  if (left <= 25 && resets > now) s = s " ↻" dur(resets - now)
  return s reset
}

BEGIN {
  while ((getline l) > 0) input = input l
  parse(input)
  size = get("context_window.context_window_size", 0) + 0
  if (size == 0) exit 0
  # Tokens in the window (input + cache, as Claude Code counts used_percentage); after /compact current_usage is
  # null until the next call, so fall back to the totals.
  if ("context_window.current_usage.input_tokens" in J)
    used = get("context_window.current_usage.input_tokens", 0) + get("context_window.current_usage.cache_read_input_tokens", 0) \
         + get("context_window.current_usage.cache_creation_input_tokens", 0)
  else used = get("context_window.total_input_tokens", 0) + 0
  srand(); now = srand()  # seconds since the epoch

  # Keep one reading per turn: append only when the figure changed.
  dir = ENVIRON["HOME"] "/.claude/statusline-state"
  sid = get("session_id", "default"); gsub(/[^A-Za-z0-9_-]/, "_", sid)
  state = dir "/" sid
  n = 0
  while ((r = (getline line < state)) > 0) reading[++n] = line
  if (r < 0) system("mkdir -p '" dir "' && find '" dir "' -type f -mtime +7 -delete 2>/dev/null")  # a new session
  close(state)
  printf "%s", size > (state ".size"); close(state ".size")
  if (used > 0 && (n == 0 || used != reading[n])) {
    reading[++n] = used
    first = n > 9 ? n - 8 : 1
    printf "" > state
    for (i = first; i <= n; i++) print reading[i] >> state
    close(state)
    m = 0; for (i = first; i <= n; i++) reading[++m] = reading[i]; n = m
  }

  esc = sprintf("%c", 27); reset = esc "[0m"; dim = esc "[2m"; bold = esc "[1m"
  pct = int(get("context_window.used_percentage", used * 100 / size))
  if (pct >= 85)      { color = esc "[31m"; icon = "●"; label = "Full" }
  else if (pct >= 70) { color = esc "[38;5;208m"; icon = "▲"; label = "Tight" }
  else if (pct >= 50) { color = esc "[33m"; icon = "◐"; label = "Filling" }
  else                { color = esc "[33m"; icon = "☀"; label = "Clear" }
  line = color icon " " bold label reset " " pct "% of context " dim fmt(used) " / " fmt(size) reset

  # Growth per turn: the differences between consecutive readings (a drop, as after /compact, counts as 0).
  m = 0; max = 0
  for (i = 2; i <= n; i++) { d = reading[i] - reading[i - 1]; if (d < 0) d = 0; g[++m] = d; if (d > max) max = d }
  narrow = (ENVIRON["COLUMNS"] + 0) > 0 && (ENVIRON["COLUMNS"] + 0) < 100
  if (m > 0) {  # in a narrow terminal keep the bars, drop the words
    split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", bars, " ")
    spark = ""
    for (i = 1; i <= m; i++) spark = spark (max > 0 ? bars[int(g[i] * 7 / max) + 1] : bars[1])
    line = line dim (narrow ? " · " : " · last turns ") reset color spark reset
    delta = reading[n] - reading[n - 1]
    line = line dim (delta >= 0 ? " ▲ +" fmt(delta) : " ▼ -" fmt(-delta)) (narrow ? "" : " last turn") reset
  }

  cost = get("cost.total_cost_usd", "")
  if (cost != "") line = line dim " · " sprintf("$%.2f", cost) reset

  # Prompt cache: when it goes cold, the next turn re-writes the whole context at the cache-write price.
  if (get("prompt_cache.warm", "") == "true" && (expires = get("prompt_cache.expires_at", 0) + 0) > now) {
    left = expires - now
    c = left <= 60 ? esc "[38;5;208m" : dim
    line = line dim " · " reset c "cache " dur(left) reset
  } else if (get("prompt_cache.warm", "") == "false" && get("prompt_cache.caching_observed", "") == "true") {
    rec = get("prompt_cache.recache_tokens_if_cold", 0) + 0
    line = line dim " · " reset esc "[38;5;208m" "cache cold" (rec ? " +" fmt(rec) : "") reset
  }

  five = get("rate_limits.five_hour.used_percentage", ""); seven = get("rate_limits.seven_day.used_percentage", "")
  if (five != "" || seven != "") {
    line = line dim " · left" reset
    if (five != "") line = line " " limit("5h", five, get("rate_limits.five_hour.resets_at", 0) + 0)
    if (seven != "") line = line " " limit("7d", seven, get("rate_limits.seven_day.resets_at", 0) + 0)
  }
  print line
}
