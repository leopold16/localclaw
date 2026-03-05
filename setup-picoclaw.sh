#!/usr/bin/env bash
set -euo pipefail

# Downloads and configures PicoClaw only (assumes Ollama + model already set up)

PICOCLAW_VERSION="v0.2.0"
PICOCLAW_HOME="${PICOCLAW_HOME:-$HOME/.picoclaw}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
die()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Detect platform
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
    Linux)  OS="Linux" ;;
    Darwin) OS="Darwin" ;;
    *)      die "Unsupported OS: $os" ;;
esac
case "$arch" in
    x86_64|amd64)   ARCH="x86_64" ;;
    arm64|aarch64)  ARCH="arm64" ;;
    armv7*)         ARCH="armv7" ;;
    armv6*)         ARCH="armv6" ;;
    riscv64)        ARCH="riscv64" ;;
    *)              die "Unsupported arch: $arch" ;;
esac

info "Platform: ${OS}/${ARCH}"

# Download PicoClaw
archive="picoclaw_${OS}_${ARCH}.tar.gz"
url="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/${archive}"

info "Downloading PicoClaw ${PICOCLAW_VERSION}..."
tmpdir="$(mktemp -d)"
curl -fSL --progress-bar "$url" -o "${tmpdir}/${archive}"
tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"

# Find and install binary
binary="${tmpdir}/picoclaw"
if [ ! -f "$binary" ]; then
    binary="$(find "$tmpdir" -name picoclaw -type f | head -1)"
    [ -z "$binary" ] && die "Could not find picoclaw binary in archive"
fi

mkdir -p "$INSTALL_DIR"
mv "$binary" "${INSTALL_DIR}/picoclaw"
chmod +x "${INSTALL_DIR}/picoclaw"
rm -rf "$tmpdir"
ok "PicoClaw installed to ${INSTALL_DIR}/picoclaw"

# Write config
mkdir -p "$PICOCLAW_HOME" "${PICOCLAW_HOME}/workspace"
cat > "${PICOCLAW_HOME}/config.json" <<'CONF'
{
  "agents": {
    "defaults": {
      "workspace": "~/.picoclaw/workspace",
      "restrict_to_workspace": true,
      "model_name": "localclaw",
      "max_tokens": 1024,
      "temperature": 0.7,
      "max_tool_iterations": 5,
      "summarize_message_threshold": 20,
      "summarize_token_percent": 75
    }
  },
  "model_list": [
    {
      "model_name": "localclaw",
      "model": "ollama/localclaw",
      "api_key": "",
      "api_base": "http://localhost:11434/v1",
      "request_timeout": 300
    }
  ],
  "channels": {},
  "tools": {
    "web": {
      "enabled": false
    },
    "exec": {
      "enabled": true
    },
    "read_file": {
      "enabled": true
    },
    "write_file": {
      "enabled": true
    },
    "list_dir": {
      "enabled": true
    }
  },
  "gateway": {
    "host": "127.0.0.1",
    "port": 18790
  }
}
CONF
ok "Config written to ${PICOCLAW_HOME}/config.json"

# Ensure PATH
case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        shell_rc="$HOME/.bashrc"
        [ "$(basename "${SHELL:-bash}")" = "zsh" ] && shell_rc="$HOME/.zshrc"
        if [ -f "$shell_rc" ]; then
            printf '\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$shell_rc"
            info "Added to PATH in ${shell_rc} — run: source ${shell_rc}"
        fi
        ;;
esac

echo ""
ok "Done! Run: picoclaw agent"
