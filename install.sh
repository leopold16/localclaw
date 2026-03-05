#!/usr/bin/env bash
set -euo pipefail

# ── NanoModel Installer ──────────────────────────────────────────────
# Blank-slate installer: sets up everything from scratch.
#   - Installs Ollama (or verifies existing install is >= 0.6)
#   - Pulls qwen3:0.6b + creates fast 2K-context variant with tool calling
#   - Downloads PicoClaw binary
#   - Writes config wired to Ollama + localclaw model
#
# Usage:
#   curl -fsSL <raw-url>/install.sh | bash
#   bash install.sh
#
# Environment overrides:
#   INSTALL_DIR      where to put the picoclaw binary  (default: ~/.local/bin)
#   PICOCLAW_HOME    config/workspace directory         (default: ~/.picoclaw)
# ─────────────────────────────────────────────────────────────────────

MODEL_BASE="qwen3:0.6b"
MODEL_NAME="localclaw"
MODEL_TAG="localclaw:latest"
OLLAMA_MIN_VERSION="0.6.0"
PICOCLAW_VERSION="v0.2.0"
PICOCLAW_HOME="${PICOCLAW_HOME:-$HOME/.picoclaw}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# ── Helpers ──────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Compare two semver strings (major.minor.patch). Returns 0 if $1 >= $2.
version_gte() {
    local IFS=.
    local i a b
    read -ra a <<< "$1"
    read -ra b <<< "$2"
    for i in 0 1 2; do
        local va="${a[$i]:-0}"
        local vb="${b[$i]:-0}"
        if (( va > vb )); then return 0; fi
        if (( va < vb )); then return 1; fi
    done
    return 0
}

# ── Prerequisite checks ─────────────────────────────────────────────

check_prerequisites() {
    local missing=()

    command_exists curl  || missing+=(curl)
    command_exists tar   || missing+=(tar)
    command_exists mktemp || missing+=(mktemp)

    if [ "${#missing[@]}" -gt 0 ]; then
        die "Missing required utilities: ${missing[*]}
Install them with your package manager, e.g.:
  apt install ${missing[*]}      # Debian/Ubuntu
  dnf install ${missing[*]}      # Fedora
  brew install ${missing[*]}     # macOS"
    fi

    ok "Prerequisites satisfied (curl, tar)"
}

# ── Detect OS / Arch ────────────────────────────────────────────────

detect_platform() {
    local os arch

    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux)  OS="Linux" ;;
        Darwin) OS="Darwin" ;;
        *)      die "Unsupported OS: $os (Linux and macOS only)" ;;
    esac

    case "$arch" in
        x86_64|amd64)   ARCH="x86_64" ;;
        arm64|aarch64)  ARCH="arm64" ;;
        armv7*)         ARCH="armv7" ;;
        armv6*)         ARCH="armv6" ;;
        riscv64)        ARCH="riscv64" ;;
        loongarch64)    ARCH="loong64" ;;
        *)              die "Unsupported architecture: $arch" ;;
    esac

    info "Platform: ${OS}/${ARCH}"
}

# ── Ollama ───────────────────────────────────────────────────────────

parse_ollama_version() {
    # `ollama --version` outputs something like "ollama version is 0.17.5"
    # or "ollama version 0.6.2" — extract the semver part.
    local raw
    raw="$(ollama --version 2>/dev/null || echo "")"
    echo "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

install_ollama() {
    if command_exists ollama; then
        local ver
        ver="$(parse_ollama_version)"

        if [ -z "$ver" ]; then
            warn "Could not determine Ollama version — proceeding (model needs >= ${OLLAMA_MIN_VERSION})"
            return
        fi

        if version_gte "$ver" "$OLLAMA_MIN_VERSION"; then
            ok "Ollama ${ver} installed (>= ${OLLAMA_MIN_VERSION} required)"
            return
        else
            die "Ollama ${ver} is too old. model requires >= ${OLLAMA_MIN_VERSION}.
Please upgrade:
  macOS:   brew upgrade ollama
  Linux:   curl -fsSL https://ollama.com/install.sh | sh"
        fi
    fi

    info "Ollama not found — installing..."

    if [ "$OS" = "Darwin" ]; then
        if command_exists brew; then
            info "Installing Ollama via Homebrew..."
            brew install ollama
        else
            die "Ollama is not installed and Homebrew is not available.
Install Ollama manually from https://ollama.com/download
or install Homebrew first:  https://brew.sh"
        fi
    elif [ "$OS" = "Linux" ]; then
        info "Installing Ollama via official install script..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    if ! command_exists ollama; then
        die "Ollama installation failed. Install manually from https://ollama.com/download"
    fi

    # Verify version after install
    local ver
    ver="$(parse_ollama_version)"
    if [ -n "$ver" ] && ! version_gte "$ver" "$OLLAMA_MIN_VERSION"; then
        die "Installed Ollama ${ver} but model requires >= ${OLLAMA_MIN_VERSION}.
Try upgrading or installing from https://ollama.com/download"
    fi

    ok "Ollama installed (${ver:-unknown version})"
}

# ── Ollama server ────────────────────────────────────────────────────

ensure_ollama_running() {
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        ok "Ollama server is running"
        return
    fi

    info "Starting Ollama server..."

    if [ "$OS" = "Darwin" ]; then
        # On macOS, Ollama.app may need to be launched, or we run `ollama serve`
        ollama serve >/dev/null 2>&1 &
    elif [ "$OS" = "Linux" ]; then
        # On Linux, ollama may be managed by systemd
        if command_exists systemctl && systemctl is-enabled ollama >/dev/null 2>&1; then
            sudo systemctl start ollama 2>/dev/null || ollama serve >/dev/null 2>&1 &
        else
            ollama serve >/dev/null 2>&1 &
        fi
    fi

    local retries=0
    while ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; do
        retries=$((retries + 1))
        if [ "$retries" -ge 30 ]; then
            die "Timed out waiting for Ollama server to start.
Try running 'ollama serve' manually in another terminal, then re-run this script."
        fi
        sleep 1
    done

    ok "Ollama server is running"
}

# ── Pull base model & create fast variant ───────────────────────────

setup_model() {
    # Check if our custom model already exists
    if ollama list 2>/dev/null | grep -q "${MODEL_NAME}"; then
        ok "Model ${MODEL_TAG} already set up"
    else
        # Pull the official model (includes full tool-calling template)
        info "Pulling ${MODEL_BASE} from Ollama (~523 MB)..."
        ollama pull "$MODEL_BASE" || die "Failed to pull ${MODEL_BASE}"
        ok "${MODEL_BASE} downloaded"

        # Create a thin variant with reduced context for CPU speed
        # Inherits everything from the base (template, tools, stop tokens)
        local modelfile
        modelfile="$(mktemp)"
        cat > "$modelfile" <<'EOF'
FROM qwen3:0.6b
PARAMETER num_ctx 2048
SYSTEM You are a concise assistant. /nothink
EOF

        info "Creating ${MODEL_TAG} (2K context for fast CPU inference)..."
        ollama create "$MODEL_TAG" -f "$modelfile" \
            || die "Failed to create model ${MODEL_TAG}"
        rm -f "$modelfile"
        ok "Model ${MODEL_TAG} created"
    fi

    # Pre-warm: load model into memory so first request isn't a cold start
    info "Warming up model (loading into memory)..."
    ollama run "$MODEL_TAG" "hi" --nowordwrap >/dev/null 2>&1 || true
    ok "Model ${MODEL_TAG} ready"
}

# ── PicoClaw binary ─────────────────────────────────────────────────

install_picoclaw() {
    if command_exists picoclaw; then
        ok "PicoClaw already installed ($(picoclaw version 2>/dev/null || echo 'installed'))"
        return
    fi

    local archive url tmpdir

    # Map arch to release asset naming
    local asset_arch="$ARCH"

    archive="picoclaw_${OS}_${asset_arch}.tar.gz"
    url="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/${archive}"

    info "Downloading PicoClaw ${PICOCLAW_VERSION} (${archive})..."

    tmpdir="$(mktemp -d)"

    curl -fSL --progress-bar "$url" -o "${tmpdir}/${archive}" \
        || die "Failed to download PicoClaw from ${url}
Check https://github.com/sipeed/picoclaw/releases for available builds."

    info "Extracting..."
    tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"

    # The tarball should contain a `picoclaw` binary at root
    if [ ! -f "${tmpdir}/picoclaw" ]; then
        # Some goreleaser archives nest in a directory
        local nested
        nested="$(find "$tmpdir" -name picoclaw -type f | head -1)"
        if [ -z "$nested" ]; then
            die "Could not find picoclaw binary in downloaded archive"
        fi
        mv "$nested" "${tmpdir}/picoclaw"
    fi

    mkdir -p "$INSTALL_DIR"
    mv "${tmpdir}/picoclaw" "${INSTALL_DIR}/picoclaw"
    chmod +x "${INSTALL_DIR}/picoclaw"
    rm -rf "$tmpdir"

    ok "PicoClaw installed to ${INSTALL_DIR}/picoclaw"
}

# ── Config ───────────────────────────────────────────────────────────

configure_picoclaw() {
    local config_file="${PICOCLAW_HOME}/config.json"

    mkdir -p "$PICOCLAW_HOME"
    mkdir -p "${PICOCLAW_HOME}/workspace"

    if [ -f "$config_file" ]; then
        warn "Config exists at ${config_file} — backing up to config.json.bak"
        cp "$config_file" "${config_file}.bak"
    fi

    cat > "$config_file" <<'CONF'
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

    ok "Config written to ${config_file}"
}

# ── PATH ─────────────────────────────────────────────────────────────

ensure_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) return ;;
    esac

    warn "${INSTALL_DIR} is not in your PATH"

    local shell_rc=""
    case "$(basename "${SHELL:-bash}")" in
        zsh)  shell_rc="$HOME/.zshrc" ;;
        bash) shell_rc="$HOME/.bashrc" ;;
        fish) shell_rc="$HOME/.config/fish/config.fish" ;;
    esac

    if [ -n "$shell_rc" ] && [ -f "$shell_rc" ]; then
        printf '\n# Added by NanoModel installer\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$shell_rc"
        info "Added ${INSTALL_DIR} to PATH in ${shell_rc}"
        info "Run: source ${shell_rc}   (or open a new terminal)"
    else
        info "Add this to your shell profile manually:"
        info "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   NanoModel Installer                    ║"
    echo "  ║   PicoClaw + Qwen3 0.6B (CPU, Ollama)    ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo ""

    detect_platform
    check_prerequisites
    echo ""

    info "Step 1/4 — Ollama"
    install_ollama
    ensure_ollama_running
    echo ""

    info "Step 2/4 — Model"
    setup_model
    echo ""

    info "Step 3/4 — PicoClaw"
    install_picoclaw
    echo ""

    info "Step 4/4 — Configuration"
    configure_picoclaw
    ensure_path
    echo ""

    echo "  ────────────────────────────────────────────"
    ok "All done!"
    echo ""
    info "Quick start:"
    echo "    picoclaw agent            # interactive chat"
    echo "    picoclaw agent -m 'hi'    # one-shot query"
    echo ""
    info "Config:    ${PICOCLAW_HOME}/config.json"
    info "Model:     ${MODEL_TAG} (Ollama @ localhost:11434)"
    info "Workspace: ${PICOCLAW_HOME}/workspace"
    echo ""
}

main "$@"
