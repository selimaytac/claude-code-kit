# context-guard

A Claude Code hook that tells the agent when the context window is getting full, so it wraps up and leaves a summary instead of being cut off by auto-compact in the middle of a task.

- At **70%**: finish the current step, write a short summary of progress and next steps, ask whether to continue or start fresh.
- At **85%**: start no new work, write the summary, and ask the user to run `/compact` or start a fresh session from it.

Each warning fires once per session. Otherwise the hook prints nothing.

## Install

```
/plugin marketplace add selimaytac/claude-code-kit
/plugin install context-guard@sel1m-kit
```

## Settings

Set these in the environment, for example in the `env` block of `~/.claude/settings.json`:

| Variable | Default | |
|---|---|---|
| `CONTEXT_GUARD_WINDOW` | `200000` | Window size in tokens. Use `1000000` for 1M-context models. |
| `CONTEXT_GUARD_WARN` | `70` | First warning, percent. |
| `CONTEXT_GUARD_STOP` | `85` | Second warning, percent. |

## How it works

On every prompt (`UserPromptSubmit`), it reads the session transcript and adds up the input and cache tokens of the last main-thread response: the same count Claude Code shows as context in use. It needs only `sh`, `sed` and `awk`.
