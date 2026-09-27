# shellcheck shell=sh
# Debian's /etc/profile resets PATH for login shells (tmux, T3's terminal and
# provider probes). Put the dev box's directories back in front. The wrappers
# in /usr/local/devbox/bin go first; they hand off to the next copy on PATH.
for dir in "$HOME/.bun/bin" "$HOME/.npm-global/bin" "$HOME/.local/bin" /usr/local/devbox/bin; do
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH" ;; esac
done
export PATH
