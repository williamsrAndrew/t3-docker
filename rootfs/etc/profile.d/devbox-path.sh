# shellcheck shell=sh
# Debian's /etc/profile resets PATH for login shells (tmux, T3's terminal and
# provider probes). Put the home-volume tool directories back in front.
for dir in "$HOME/.bun/bin" "$HOME/.npm-global/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH" ;; esac
done
export PATH
