# t3-docker

A self-hosted remote development box built around [T3 Code](https://github.com/pingdotgg/t3code). Run it on a server (like TrueNAS). Then drive Claude Code and Codex from a browser, the T3 desktop app, or your phone.

| What | Where |
|---|---|
| T3 Code web UI + server | `:3773` |
| Web terminal (ttyd + tmux, basic auth) | `:7681` |
| Your dev servers | `:3000-3010`, `:5173` |

**Included:** T3 Code, Claude Code, Codex, GitHub CLI, Vercel CLI, Node 24 LTS, npm, pnpm, bun, TypeScript/tsx, Python 3 + uv, a build toolchain, headless Chromium with a Playwright MCP server already registered for Claude and Codex, and git/git-lfs, ripgrep, fd, fzf, bat, jq, yq, tmux, htop, shellcheck, sqlite3, psql and redis-cli.

## Quick start (TrueNAS SCALE)

1. **Create two datasets**, for example `apps/t3-dev/home` and `apps/t3-dev/workspace`. Give them to your TrueNAS user. Note that user's uid/gid (Credentials → Users; usually 3000+).
2. **Let TrueNAS pull the private image** (see [Private registry](#private-github-container-registry)).
3. **Apps → Discover Apps → ⋮ → Install via YAML.** Paste [`deploy/truenas.yaml`](deploy/truenas.yaml) and fill in every `CHANGE`.
4. **Open the app logs.** Once the server is ready it prints a pairing link and QR code:
   ```
   Pair a device with T3 Code (link expires in 30m, single use):
       http://192.168.2.30:3773/pair#token=...
   ```
   Use that link. **Ignore T3's own "Pairing URL" line above it.** That one uses the container's internal IP.
5. **Sign in to your tools once.** Open the web terminal at `http://192.168.2.30:7681` and run:
   ```bash
   claude auth login          # prints a URL; finish in any browser
   codex login --device-auth
   gh auth login              # then git push/pull over https just works
   vercel login
   devbox-doctor              # checks everything
   ```
   These logins are stored in the home volume and survive updates and recreates.

## Quick start (plain Docker)

```bash
cp .env.example .env   # edit it
docker compose up -d
docker compose logs -f t3-dev
```

## Everyday commands

| Command | Does |
|---|---|
| `t3-pair` | Makes a new pairing link and QR code for another device (`--ttl 2h` to change the expiry) |
| `devbox-doctor` | Shows tool versions, login status, and whether the volumes are mounted |
| `devbox-mcp-setup` | Re-registers the Playwright MCP server with Claude and Codex |
| `supervisorctl restart t3code` | Restarts T3 Code (run as root: `docker exec t3-dev supervisorctl ...`) |

The helper scripts switch to the `dev` user on their own, so `docker exec t3-dev t3-pair` works. To get a shell, use `docker exec -it -u dev t3-dev bash -l`.

## What persists

Everything under `/home/dev` is on your volume:

| Path | Contents |
|---|---|
| `~/.t3` | T3 Code threads, projects, paired devices, settings |
| `~/.claude`, `~/.claude.json` | Claude Code login, settings, memory, MCP servers |
| `~/.codex` | Codex login and config |
| `~/.config/gh` | GitHub CLI login |
| `~/.local/share/com.vercel.cli` | Vercel login |
| `~/.gitconfig`, `~/.ssh` | Git identity, credential helper, SSH keys |
| `~/.bash_history`, `~/.bashrc`, `~/.tmux.conf` | Your shell setup (seeded once, never overwritten) |
| `~/.npm-global`, `~/.bun`, `~/.local/bin`, `~/.cache` | Anything you install yourself with `npm i -g`, `bun add -g`, `uv tool install`, and so on |

`/workspace` is your code. Anything else in the container, including `apt install`s, is reset when the image updates. If you need something permanently, add it to the Dockerfile.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `1000` | uid/gid of the `dev` user. Match your datasets' owner. |
| `TZ` | `UTC` | Timezone |
| `T3_PUBLIC_URL` | — | The URL your devices use, e.g. `http://192.168.2.30:3773`. Pairing links point here. |
| `T3_PAIR_TTL` | `30m` | How long `t3-pair` links stay valid |
| `TTYD_CREDENTIAL` | — | `user:password` for the web terminal. **Empty disables it.** |
| `TTYD_ENABLE` | `true` | Set `false` to turn the web terminal off entirely |
| `ALLOW_SUDO` | `true` | Passwordless sudo for `dev` (and therefore for agents) |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | — | Written to `~/.gitconfig` on every start |
| `GH_TOKEN` | — | Optional alternative to `gh auth login` |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `VERCEL_TOKEN` | — | Optional alternatives to logging in interactively |
| `NODE_OPTIONS` | `--max-old-space-size=4096` | Node heap size |
| `CHOKIDAR_USEPOLLING`, `WATCHPACK_POLLING` | — | Set `true` if `/workspace` is on SMB/NFS and hot reload misses changes |
| `T3CODE_PORT`, `TTYD_PORT` | `3773`, `7681` | Internal ports (change the published ports instead) |

**Dev servers** must listen on `0.0.0.0` to be reachable from your LAN (for example `vite --host`, `next dev -H 0.0.0.0`). Then open `http://192.168.2.30:5173`.

## Private GitHub Container Registry

The workflow in `.github/workflows/build.yml` builds the image and pushes it to `ghcr.io/williamsrandrew/t3-docker`. It runs on every push to `main`, on `v*` tags, and **every Monday**, so Claude Code, Codex and T3 Code stay current. Images pushed from a private repo are private too.

To let TrueNAS pull it:

1. Create a **classic personal access token** with only the `read:packages` scope (GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)).
2. Give it to TrueNAS in one of these ways:
   - **Apps → Configuration → Manage Container Image Registries** → add `ghcr.io` with your GitHub username and the token (if your TrueNAS version has this screen), or
   - in **System → Shell**: `sudo docker login ghcr.io -u williamsrAndrew` and paste the token as the password.

## Updating

- **Image** (tools, T3 Code): pull and redeploy the app. In TrueNAS, edit the app and save, or use the update button. Your home volume and workspace are untouched.
- **In-place updates inside the container are lost on recreate.** Claude's auto-updater is disabled for that reason. An `npm i -g` you run yourself goes to `~/.npm-global` and *does* persist, and it takes priority over the image's copy. `rm -rf ~/.npm-global/*` returns you to the image versions.
- **Pin a T3 Code version**: build with `--build-arg T3CODE_VERSION=0.0.42`, or pass it to the workflow's manual run.
- **Bake in more npm CLIs**: `--build-arg EXTRA_NPM_PACKAGES="opencode-ai @google/gemini-cli"`.

## Security notes

- T3 Code only accepts devices you've paired, but the connection is **plain HTTP**. Keep it on your LAN or VPN, and don't port-forward it to the internet. For remote access, T3's built-in `t3 connect` or Tailscale are the supported routes.
- ttyd uses HTTP basic auth over plain HTTP, and it gives a shell with (by default) sudo. Use a strong password, or set `TTYD_ENABLE=false` once your logins are done.
- The server's startup logs contain a live pairing token. Treat the logs as sensitive.
- Chromium runs with `--no-sandbox`. The container is the sandbox, so no extra privileges or `seccomp=unconfined` are needed.
