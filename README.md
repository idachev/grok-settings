# .grok

My personal [Grok Build](https://x.ai/news/grok-build-cli) CLI configuration — a snapshot of `~/.grok` minus runtime state, credentials, and memory (see `.gitignore`).

## What's tracked

| File / Dir | Purpose |
|---|---|
| `config.toml` | UI prefs, plugins, memory toggle, marketplace source |
| `installed-plugins/registry.json` | Which plugins were installed (URL + commit), without the full plugin trees |
| `.gitignore` | Keeps secrets, sessions, caches, and memory off the remote |
| `README-grok.md` | Upstream Grok CLI product README (local reference only; not my config) |

## What's intentionally local (not in git)

- **`auth.json`** / MCP credentials — login tokens
- **`sessions/`**, **`logs/`**, caches, binaries, marketplace clones
- **`memory/`** — cross-session notes (often project-named; kept private)
- **`trusted_folders.toml`** — absolute machine paths

## Using this on another machine

1. Install Grok (`curl -fsSL https://x.ai/cli/install.sh | bash` or your usual path).
2. Clone into `~/.grok` (or copy the tracked files over an existing install).
3. Run `grok login` so credentials stay local — never copy `auth.json` from another host.
4. Reinstall plugins from the registry / marketplace as needed.

Sibling config repos: [claude-code-settings](https://github.com/idachev/claude-code-settings), [own-debian-configs](https://github.com/idachev/own-debian-configs).
