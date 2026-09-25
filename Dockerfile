# syntax=docker/dockerfile:1.7
#
# t3-docker — a remote development box built around T3 Code.
#
#   T3 Code server (port 3773)  ─ web UI + agent orchestration
#   ttyd web terminal (7681)    ─ tmux shell in the browser, for logins and odd jobs
#   Claude Code, Codex, gh, vercel, node/npm/pnpm/bun, python/uv, headless Chromium
#
# Everything is installed outside /home/dev so the home directory can be a
# persistent bind mount without hiding any tools.

ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-trixie-slim

ARG TARGETARCH
# Empty = latest stable. Pin (e.g. 0.0.42) for reproducible builds.
ARG T3CODE_VERSION=""
ARG T3CODE_CHANNEL=stable
ARG TTYD_VERSION=1.7.7
ARG YQ_VERSION=v4.53.6
# Extra global npm packages to bake in, space separated (e.g. "opencode-ai @google/gemini-cli").
ARG EXTRA_NPM_PACKAGES=""

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # core
        ca-certificates curl wget gnupg sudo tini supervisor tzdata locales \
        bash-completion less nano vim-tiny file rsync procps psmisc \
        # vcs / ssh
        git git-lfs openssh-client \
        # build toolchain for native node modules / python wheels
        build-essential pkg-config python3 python3-venv python3-pip python-is-python3 \
        # cli quality of life
        jq ripgrep fd-find fzf bat tree tmux htop lsof strace shellcheck \
        unzip zip xz-utils bzip2 zstd qrencode \
        # networking
        iproute2 iputils-ping bind9-dnsutils netcat-openbsd \
        # database clients
        sqlite3 postgresql-client redis-tools \
        # headless browser
        chromium fonts-liberation fonts-noto-color-emoji \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI (official apt repo) ───────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ── Static binaries: ttyd, yq ────────────────────────────────────────────────
RUN case "${TARGETARCH:-amd64}" in \
        amd64) ttyd_arch=x86_64 ;; \
        arm64) ttyd_arch=aarch64 ;; \
        *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && cd /tmp \
    && curl -fsSLO "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}" \
    && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS" \
        | grep " ttyd.${ttyd_arch}\$" | sha256sum -c - \
    && install -m 0755 "ttyd.${ttyd_arch}" /usr/local/bin/ttyd \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH:-amd64}" \
        -o /usr/local/bin/yq \
    && chmod 0755 /usr/local/bin/yq \
    && rm -f /tmp/ttyd.*

# ── Bun + uv (installed system-wide) ─────────────────────────────────────────
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash \
    && curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
    && bun --version && uv --version

# ── Global npm tooling ───────────────────────────────────────────────────────
# Agent CLIs update fast; rebuild the image (CI does it weekly) to pick up new versions.
RUN npm install -g --no-fund --no-audit \
        npm@latest pnpm \
        @anthropic-ai/claude-code \
        @openai/codex \
        vercel \
        typescript tsx nodemon serve prettier \
        @playwright/mcp \
        ${EXTRA_NPM_PACKAGES} \
    && npm cache clean --force \
    && claude --version && codex --version && vercel --version

# ── T3 Code ──────────────────────────────────────────────────────────────────
# The self-contained runtime lives in /opt/t3; user state goes to $T3CODE_HOME
# (/home/dev/.t3) at runtime, which is on the persistent volume.
RUN curl -fsSL https://t3.codes/install.sh \
        | T3CODE_HOME=/opt/t3 T3CODE_INSTALL_BIN_DIR=/usr/local/bin \
          T3CODE_VERSION="${T3CODE_VERSION}" T3CODE_CHANNEL="${T3CODE_CHANNEL}" sh \
    && chmod -R a+rX /opt/t3 \
    && t3 --version

# ── The `dev` user (renamed from the base image's `node` user, uid 1000) ─────
RUN usermod -l dev -d /home/dev -m -s /bin/bash node \
    && groupmod -n dev node \
    && mkdir -p /workspace \
    && chown dev:dev /workspace

COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
COPY --chmod=0755 rootfs/usr/local/devbox/bin/ /usr/local/devbox/bin/
COPY rootfs/usr/local/share/devbox/ /usr/local/share/devbox/
COPY rootfs/etc/ /etc/

# ttyd's built-in page + a small script that makes Ctrl+V paste.
RUN ttyd --port 7999 --interface lo true & pid=$!; \
    for _ in $(seq 40); do curl -fsS http://127.0.0.1:7999/ -o /tmp/ttyd.html && break; sleep 0.25; done; \
    kill "$pid"; \
    grep -q '</body>' /tmp/ttyd.html \
    && perl -0pe 'BEGIN { local $/; open F, "/usr/local/share/devbox/ttyd-paste.html" or die; $js = <F> } s{</body>}{$js</body>}' \
        /tmp/ttyd.html > /tmp/ttyd-patched.html \
    && grep -q 'plainCtrlV' /tmp/ttyd-patched.html \
    && mv /tmp/ttyd-patched.html /usr/local/share/devbox/ttyd-index.html \
    && rm -f /tmp/ttyd.html

ENV HOME=/home/dev \
    SHELL=/bin/bash \
    TZ=UTC \
    PUID=1000 \
    PGID=1000 \
    # T3 Code
    T3CODE_HOME=/home/dev/.t3 \
    T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_NO_BROWSER=true \
    T3_PUBLIC_URL="" \
    T3_PAIR_TTL=30m \
    # optional username/password login in front of T3 Code (enabled when a password is set)
    T3_LOGIN_USER=dev \
    T3_LOGIN_PASSWORD="" \
    T3_LOGIN_DAYS=365 \
    T3_INTERNAL_PORT=3772 \
    # web terminal
    TTYD_ENABLE=true \
    TTYD_PORT=7681 \
    TTYD_CREDENTIAL="" \
    # container behaviour
    ALLOW_SUDO=true \
    GIT_USER_NAME="" \
    GIT_USER_EMAIL="" \
    # user-level installs land on the persistent volume and win over image versions
    NPM_CONFIG_PREFIX=/home/dev/.npm-global \
    BUN_INSTALL=/home/dev/.bun \
    PATH=/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.bun/bin:/usr/local/devbox/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    # image-managed CLIs are updated by rebuilding, not in place
    DISABLE_AUTOUPDATER=1 \
    # browsers
    CHROME_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=true \
    NODE_OPTIONS=--max-old-space-size=4096

WORKDIR /workspace
EXPOSE 3773 7681

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${T3CODE_PORT}/health" >/dev/null || exit 1

LABEL org.opencontainers.image.title="t3-docker" \
      org.opencontainers.image.description="Remote dev box: T3 Code + Claude Code + Codex + gh + vercel + node/bun + headless Chromium"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/devbox-entrypoint"]
