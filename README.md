# t3-docker

A self-hosted remote development box built around [T3 Code](https://github.com/pingdotgg/t3code). Run it on any machine with Docker, such as a home server, a NAS or a spare PC. Then drive Claude Code and Codex from a browser, the T3 desktop app, or your phone.

| What | Where |
|---|---|
| T3 Code web UI + server | `:3773` |
| Web terminal (ttyd + tmux, basic auth) | `:7681` |
| Dev-server preview | `:3000` |

**Included:** T3 Code, Claude Code, Codex, GitHub CLI, Vercel CLI, Node 24 LTS, npm, pnpm, bun, TypeScript/tsx, Python 3 + uv, a build toolchain, headless Chromium with a Playwright MCP server already registered for Claude and Codex, and git/git-lfs, ripgrep, fd, fzf, bat, jq, yq, tmux, htop, shellcheck, sqlite3, psql and redis-cli.

The image is published at `ghcr.io/williamsrandrew/t3-docker` for `linux/amd64`.

> [!WARNING]
> **This is for your LAN or VPN only. Don't expose its ports to the internet.** Anyone who gets in has a shell with passwordless sudo, your Claude/Codex/GitHub logins, and all of your code. Every service here uses plain HTTP. See [Security](#security) before you deploy.

## Quick start (Docker Compose)

1. **Get the compose file and the example settings:**
   ```bash
   git clone https://github.com/williamsrAndrew/t3-docker.git
   cd t3-docker
   cp .env.example .env
   ```
2. **Edit `.env`.** At a minimum, set these:
   - `T3_PUBLIC_URL`: the address your other devices use to reach this machine, for example `http://192.168.1.50:3773`. Pairing links point here.
   - `T3_LOGIN_PASSWORD`: turns on the browser login. Leave it empty to use T3's pairing links instead (see [Signing in](#signing-in)).
   - `PUID` / `PGID`: the owner of your data folders on the host (run `id` to see yours).
   - `DATA_DIR` / `WORKSPACE_DIR`: where the home folder and your projects live on the host (defaults `./data` and `./workspace`).
   - `TZ`, `GIT_USER_NAME`, `GIT_USER_EMAIL`.
3. **Start it:**
   ```bash
   docker compose up -d
   docker compose logs -f t3-dev
   ```
4. **Open `T3_PUBLIC_URL`** (for example `http://192.168.1.50:3773`) and sign in with `T3_LOGIN_USER` / `T3_LOGIN_PASSWORD`. You'll stay signed in for `T3_LOGIN_DAYS` (365 by default).
5. **Sign in to your tools once, from the T3 page.** T3's setup wizard (step 2, **Agents**) has a **Sign in** button next to each agent that isn't signed in. It opens a terminal inside the page with the command ready: press Enter. You can also open a terminal in any thread and run the commands yourself:
   ```bash
   claude auth login   # open the URL, approve, copy the code, paste it back, press Enter
   codex login         # shows a URL and a short code; enter the code on that page
   gh auth login       # choose "Login with a web browser"; also sets up git push/pull
   vercel login
   devbox-doctor       # checks everything
   ```
   These logins are stored in the home volume and survive updates and recreates. See [Signing in to tools](#signing-in-to-tools) if something doesn't work.

`compose.yaml` pulls the published image. If you've changed the Dockerfile, run `docker compose build` to build it yourself instead.

Using TrueNAS SCALE? See [TrueNAS SCALE](#truenas-scale).

## Signing in

There are two ways to get into the web UI. You can use both at once.

### Username and password

Set `T3_LOGIN_PASSWORD` (and optionally `T3_LOGIN_USER`, default `dev`) to turn on a small login gate in front of T3 Code:

```
browser ─► :3773 login gate ─► T3 Code on internal :3772 (not published)
```

- Browsers get a login page. After you sign in, the gate sets a signed cookie that lasts `T3_LOGIN_DAYS` (default **365**). It forwards your requests to T3 with a long-lived T3 token that it keeps in `~/.t3/devbox-login-token`.
- The cookie survives container restarts and image updates. Changing the username or password signs every browser out. To sign one browser out, go to `/__login/logout`.
- The login allows 5 failed attempts per IP address per 15 minutes.
- The **phone and desktop apps** still pair with a QR code from `t3-pair`. The gate passes their requests straight through, and T3 checks them itself.
- The gate's T3 token shows up as `login-gate` under **Settings → Connections**. If you revoke it, every browser gets locked out until the gate issues a new one: run `supervisorctl restart login-gate` as root, or restart the container.
- Read [what the login gate does and doesn't protect against](#security) first.

### Pairing links (T3's built-in method)

With `T3_LOGIN_PASSWORD` empty, T3 uses its own device pairing. Open the one-time link from the container logs or `t3-pair`, then ignore T3's own "Pairing URL" line in the logs, since that one uses the container's internal IP. Pairing gives the browser a session that lasts **30 days**, a limit set inside T3 that can't be changed. It's stored on the home volume, so restarts don't sign you out. You need a new link for each new browser or device, and after 30 days.

T3 also has **T3 Connect**: sign in with a T3 account on every device, with no pairing and access from anywhere. It goes through T3's cloud relay. Run `t3 connect` in a terminal to set it up.

To see or revoke paired devices, go to **Settings → Connections** in the web UI, or run `t3 auth session list`.

## Signing in to tools

- **Pasting.**
  - In **T3's terminal**: **Ctrl+Shift+V** or **Shift+Insert** on Windows/Linux, **Cmd+V** on Mac. Plain Ctrl+V goes to the program, as it does in desktop terminals.
  - In the **web terminal (ttyd)**: plain **Ctrl+V** pastes too.
  - Right-click → Paste may not work, because browsers disable the clipboard API on plain-HTTP pages.
- **Claude's "Paste code here" prompt shows nothing as you paste or type.** That's normal: the code is hidden like a password. Paste once and press Enter.
- **Claude may show as "Authenticated" in T3 before you've signed in.** T3's check only confirms the CLI starts. If there's no Sign in button, run `claude auth login` in a terminal anyway. `claude auth status` shows the real state.
- **`codex login` automatically uses the device-code flow** (`--device-auth`). The normal flow expects a browser on the same machine and can't finish on a server.
- The web terminal on `:7681` is a fallback for when T3 isn't running. It's off unless you set `TTYD_CREDENTIAL`.

## Everyday commands

| Command | Does |
|---|---|
| `t3-pair` | Makes a new pairing link and QR code for the phone or desktop app, or a browser when the login gate is off (`--ttl 2h` to change the expiry) |
| `devbox-doctor` | Shows tool versions, login status, and whether the volumes are mounted |
| `devbox-update` | Installs newer T3 Code / Claude Code / Codex releases now (restart T3 to use a new T3 version) |
| `devbox-mcp-setup` | Re-registers the Playwright MCP server with Claude and Codex |
| `supervisorctl restart t3code` | Restarts T3 Code (run as root: `docker exec t3-dev supervisorctl ...`) |

The helper scripts switch to the `dev` user on their own, so `docker exec t3-dev t3-pair` works. To get a shell, use `docker exec -it -u dev t3-dev bash -l`.

## What persists

Everything under `/home/dev` is on your volume:

| Path | Contents |
|---|---|
| `~/.t3` | T3 Code threads, projects, paired devices, settings, and T3 versions installed by updates (`runtime/`) |
| `~/.claude`, `~/.claude.json` | Claude Code login, settings, memory, MCP servers |
| `~/.codex` | Codex login and config |
| `~/.config/gh` | GitHub CLI login |
| `~/.local/share/com.vercel.cli` | Vercel login |
| `~/.gitconfig`, `~/.ssh` | Git identity, credential helper, SSH keys |
| `~/.bash_history`, `~/.bashrc`, `~/.tmux.conf` | Your shell setup (seeded once, never overwritten) |
| `~/.npm-global` | Claude Code and Codex (kept up to date here), plus anything you `npm i -g` |
| `~/.bun`, `~/.local/bin`, `~/.cache` | Anything you install with `bun add -g`, `uv tool install`, and so on |

`/workspace` is your code. Anything else in the container, including `apt install`s, is reset when the image updates. If you need something permanently, add it to the Dockerfile.

## Headless browser (Chromium)

The image includes Chromium (about 390 MB with its fonts) so **agents can use a browser inside the container**:

- **For Claude Code and Codex.** A [Playwright MCP](https://github.com/microsoft/playwright-mcp) server is registered for both on first start. It lets them open pages, click, fill forms, take screenshots and read console errors, so they can check their own web work. It runs headless and isolated, so there are no saved logins between sessions. Run `devbox-mcp-setup` to register it again, for example after resetting `~/.claude`.
- **For your project's tools.** `CHROME_PATH` and `PUPPETEER_EXECUTABLE_PATH` point at it, so Puppeteer and similar tools use it rather than downloading their own. A project's own Playwright test setup still installs its own browsers into `~/.cache/ms-playwright`.
- **It sees the container's network.** Agents can open a dev server at `http://localhost:<port>` without publishing any ports.

**This is not T3's Browser panel** (**Settings → Integrations → Browser**). That panel is built into the T3 **desktop app** and runs on the computer you're viewing from, which is why the web UI says it's desktop-only. To use it, connect the T3 desktop app to this server; agents can then drive that browser through T3's preview tools. It loads pages from your computer, so the app you're previewing must be reachable from there. That's what the published port 3000 is for (see [Dev-server preview](#dev-server-preview)).

Chromium needs `shm_size: 2g` (already in the compose files) and runs with `--no-sandbox`; see [Security](#security).

## Dev-server preview

One port, `3000`, is published so you can open a running app from your laptop. Start the app on that port, listening on all interfaces: `vite --host 0.0.0.0 --port 3000`, `next dev -H 0.0.0.0 -p 3000`, or `PORT=3000 HOST=0.0.0.0 npm start`. Then open `http://<your-server>:3000`. Agents don't need it: they test apps inside the container with the built-in headless Chromium.

If 3000 is taken on the host, set `DEV_PORT` in `.env` (or change only the left side of the port mapping, for example `"3100:3000"`), or remove the line.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `1000` | uid/gid of the `dev` user. Match the owner of your data folders. |
| `TZ` | `UTC` | Timezone |
| `T3_PUBLIC_URL` | — | The URL your devices use, e.g. `http://192.168.1.50:3773`. Pairing links point here. |
| `T3_PAIR_TTL` | `30m` | How long `t3-pair` links stay valid |
| `T3_LOGIN_PASSWORD` | — | Turns on the username/password login gate. Empty = pairing only. |
| `T3_LOGIN_USER` | `dev` | Login gate username |
| `T3_LOGIN_DAYS` | `365` | How long a browser stays signed in through the gate |
| `T3_INTERNAL_PORT` | `3772` | Internal T3 port when the gate is on (not published) |
| `TTYD_CREDENTIAL` | — | `user:password` for the web terminal. **Empty disables it.** |
| `TTYD_ENABLE` | `true` | Set `false` to turn the web terminal off entirely |
| `ALLOW_SUDO` | `true` | Passwordless sudo for `dev` (and therefore for agents) |
| `AUTO_UPDATE` | `true` | Install new T3 Code / Claude Code / Codex releases into the home volume on each start |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | — | Written to `~/.gitconfig` on every start |
| `GH_TOKEN` | — | Optional alternative to `gh auth login` |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `VERCEL_TOKEN` | — | Optional alternatives to logging in interactively |
| `NODE_OPTIONS` | `--max-old-space-size=4096` | Node heap size |
| `CHOKIDAR_USEPOLLING`, `WATCHPACK_POLLING` | — | Set `true` if `/workspace` is on SMB/NFS and hot reload misses changes |
| `T3CODE_PORT`, `TTYD_PORT` | `3773`, `7681` | Internal ports (change the published ports instead) |

These compose-only settings go in `.env` too: `IMAGE`, `DATA_DIR`, `WORKSPACE_DIR`, `DEV_PORT`.

## Updating

There are three ways updates arrive. You can use any of them.

**1. From the T3 UI**
- **Claude Code / Codex:** when a new version is out, **Settings → Providers** shows **Update available** with an **Update** button. It installs into `~/.npm-global` on your home volume, so it persists.
- **T3 Code itself:** T3 runs under its own service launcher, so the T3 apps can update this server in place. You'll see **Update server** when your phone or desktop app is newer than the server, or under **Settings → Environments → Check for updates** in the mobile app. New versions are kept in `~/.t3/runtime`.

**2. Automatically on every container start (`AUTO_UPDATE=true`, the default)**
- About a minute after startup, `devbox-update` installs any newer Claude Code, Codex and T3 Code releases into the home volume. The logs show a summary line: `[devbox-update] claude-code …, codex …, t3 …`.
- If T3 Code itself was updated, T3 restarts once to switch over. Running agents are interrupted; turn on **Settings → General → Continue threads after restarts** to resume them.
- Run `devbox-update` in a terminal to check right away. Set `AUTO_UPDATE=false` to only update when you choose.

**3. A new image**
- Once a day, GitHub Actions checks for new T3 Code, Claude Code and Codex releases, and rebuilds and pushes the image only if one changed. The versions are pinned and recorded as image labels. A weekly rebuild (Mondays) also picks up Debian security updates and the other tools.
- Docker doesn't redeploy by itself. To switch to the newest image:
  ```bash
  docker compose pull
  docker compose up -d
  ```
  Your home volume and workspace are untouched. Tools like [Watchtower](https://github.com/containrrr/watchtower) can do this for you.

**Newest wins:** the image ships a copy of each tool. On every start, if the image's copy is newer than the one in your home folder (for example after pulling a new image), the image's copy is used. Otherwise your updated copy is kept.

**Checking versions**
- Inside the container: `devbox-doctor`, or `claude --version`, `codex --version`, `t3 --version`.
- The image: `docker inspect t3-dev --format '{{ json .Config.Labels }}'` shows `dev.t3docker.version.*` (the versions baked into the image) and `org.opencontainers.image.revision` (the git commit).

**Resetting to the image's versions:** `rm -rf ~/.npm-global/lib/node_modules/@anthropic-ai ~/.npm-global/lib/node_modules/@openai`, then restart the container.

## TrueNAS SCALE

TrueNAS doesn't read `.env` files, so use [`deploy/truenas.yaml`](deploy/truenas.yaml), which has the settings inline.

1. **Create two datasets**, for example `POOL/apps/t3-dev/home` and `POOL/apps/t3-dev/workspace`, using the **Apps** dataset preset so they're owned by TrueNAS's `apps` user (uid/gid 568). The compose file already uses `PUID`/`PGID` 568. If you'd rather use your own TrueNAS user, set both to that user's uid/gid instead. The container remaps its `dev` user to match on startup.
2. **Apps → Discover Apps → ⋮ → Install via YAML.** Name the app `t3-dev` and paste in [`deploy/truenas.yaml`](deploy/truenas.yaml). Change every line marked `CHANGE`: the dataset paths, `TZ`, `T3_PUBLIC_URL` (your NAS's address), the passwords, and your git identity.
3. Continue from step 4 of the [quick start](#quick-start-docker-compose).

**Updating:** TrueNAS checks custom apps' images against the registry and shows **Update available** with an **Update** button when `latest` moves. The check runs periodically, so the badge can take a while to appear after a new image is pushed. The compose file also sets `pull_policy: always`, so **Apps → t3-dev → Edit → Save** pulls the newest image right away. Your datasets are untouched.

To see the running image's versions, run `sudo docker inspect t3-dev --format '{{ json .Config.Labels }}'` in **System → Shell**.

## Building your own image

The workflow in [`.github/workflows/build.yml`](.github/workflows/build.yml) builds the image and pushes it to `ghcr.io/<owner>/<repo>`. It runs on every push to `main`, on `v*` tags, daily (to check for new releases) and weekly. In a fork, it pushes to your own GHCR namespace. New GHCR packages start out private: to pull without logging in, make the package public under **your profile → Packages → t3-docker → Package settings → Change visibility**.

Build options: `--build-arg T3CODE_VERSION=0.0.42` (also in the workflow's manual run), `CLAUDE_CODE_VERSION`, `CODEX_VERSION`, and `EXTRA_NPM_PACKAGES="opencode-ai @google/gemini-cli"` to bake in more npm CLIs.

## Security

This container is a remote shell for AI agents. Whoever can sign in to T3 Code or the web terminal can run any command as `dev`, and with the default `ALLOW_SUDO=true` as root inside the container. They also get your Claude, Codex, GitHub and Vercel logins, your SSH keys, and everything in `/workspace`. Treat access to it like SSH access to the host.

**Keep it on a network you trust.** Don't port-forward `3773`, `7681` or `3000` to the internet, and don't put them on a public cloud VM without a firewall. For access from outside your home, use a VPN such as [Tailscale](https://tailscale.com) or WireGuard, or T3's own `t3 connect`.

**The login gate is a convenience for a trusted LAN, not internet-grade authentication.**
- It's a small proxy written for this project. It hasn't been independently audited.
- It runs over **plain HTTP**. Your password and your session cookie cross the network unencrypted, so anyone who can see your traffic (shared Wi-Fi, a compromised device on the LAN) can capture them and sign in as you.
- The rate limit (5 failures per IP per 15 minutes) slows down guessing but doesn't stop it. Use a long, random password.
- If you put HTTPS in front with a reverse proxy, every request reaches the gate from the proxy's IP, so the rate limit applies to everyone at once. Don't treat HTTPS plus the gate as safe for the internet either.

**The web terminal (ttyd) is even more sensitive.**
- It's a full shell, with sudo by default, behind HTTP basic auth.
- Basic auth over plain HTTP sends your username and password with **every request**, readable by anyone watching the traffic. There's no rate limit.
- It's off unless you set `TTYD_CREDENTIAL`. T3 Code has its own terminal, so most people never need ttyd. If you turn it on for setup, set `TTYD_ENABLE=false` or remove `TTYD_CREDENTIAL` afterwards.

**Other things to know**
- The dev-server preview port (`3000`) has no authentication at all. Anything you run there is open to your whole network.
- The server's startup logs contain a live pairing token. Treat the logs as sensitive.
- Set `ALLOW_SUDO=false` if agents don't need root. They can still install tools as `dev` into the home volume.
- Chromium runs with `--no-sandbox`. The container is the sandbox, so no extra privileges or `seccomp=unconfined` are needed.

## License

[MIT](LICENSE), the same as T3 Code. T3 Code, Claude Code, Codex and the other bundled tools keep their own licenses.
