# claude-code-kit

Small, measured add-ons for [Claude Code](https://code.claude.com): status lines, hooks, skills and agents. Each one has its own folder with what it does, how to install it, and before/after numbers where speed matters.

## What's inside

| | What it does | Install |
|---|---|---|
| [statusline](statusline/) | Context use, growth per turn, prompt cache timer and rate-limit resets in one awk process, about 3x faster than the usual bash + jq script | copy one file + one setting |
| [context-guard](plugins/context-guard/) | Tells the agent at 70% and 85% of the context window to wrap up and leave a summary | plugin |

## Install a plugin

This repo is a plugin marketplace. In Claude Code:

```
/plugin marketplace add selimaytac/claude-code-kit
/plugin install context-guard@sel1m-kit
```

Items that Claude Code can't load as a plugin (like the status line) have copy-paste steps in their own README.

## Contributing

Issues and pull requests are welcome. Keep each add-on small, with a README that says what it does, how to install it, and how it was tested.

## License

[MIT](LICENSE)
