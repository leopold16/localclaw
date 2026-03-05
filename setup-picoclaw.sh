#!/usr/bin/env bash
set -euo pipefail

# Interactive PicoClaw installer with provider + Telegram onboarding

PICOCLAW_VERSION="v0.2.0"
PICOCLAW_HOME="${PICOCLAW_HOME:-$HOME/.picoclaw}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ── Interactive prompt helpers ──────────────────────────────────────

ask() {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        printf '\033[1;37m%s\033[0m \033[2m[%s]\033[0m: ' "$prompt" "$default"
    else
        printf '\033[1;37m%s\033[0m: ' "$prompt"
    fi
    read -r REPLY </dev/tty
    REPLY="${REPLY:-$default}"
}

ask_secret() {
    local prompt="$1"
    printf '\033[1;37m%s\033[0m: ' "$prompt"
    read -rs REPLY </dev/tty
    echo ""
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    ask "$prompt (y/n)" "$default"
    case "$REPLY" in
        [yY]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ── Provider onboarding ────────────────────────────────────────────

onboard_provider() {
    echo ""
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   PicoClaw Setup                         ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo ""

    echo "  Choose your LLM provider:"
    echo ""
    echo "    1) Ollama       (local, free, needs ollama running)"
    echo "    2) OpenRouter   (cloud, many models, needs API key)"
    echo ""
    ask "  Select [1/2]" "1"
    local choice="$REPLY"

    case "$choice" in
        1) onboard_ollama ;;
        2) onboard_openrouter ;;
        *) die "Invalid choice: $choice" ;;
    esac
}

onboard_ollama() {
    echo ""
    info "Ollama setup"
    echo ""

    if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        warn "Ollama doesn't seem to be running on localhost:11434"
        ask "Ollama API base URL" "http://localhost:11434"
        PROVIDER_API_BASE="${REPLY}/v1"
    else
        ok "Ollama is running"
        PROVIDER_API_BASE="http://localhost:11434/v1"
    fi

    if command -v ollama >/dev/null 2>&1; then
        echo ""
        info "Available models:"
        ollama list 2>/dev/null | tail -n +2 | awk '{print "    " $1}' || true
        echo ""
    fi

    ask "Model name (as shown in ollama list)" "qwen3:0.6b"
    local ollama_model="$REPLY"

    PROVIDER_MODEL_NAME="$(echo "$ollama_model" | tr ':/' '-')"
    PROVIDER_MODEL="ollama/${ollama_model}"
    PROVIDER_API_KEY=""
    PROVIDER_TIMEOUT=300
    PROVIDER_MAX_TOKENS=1024

    ok "Using ${ollama_model} via Ollama"
}

onboard_openrouter() {
    echo ""
    info "OpenRouter setup"
    echo "  Get your API key at: https://openrouter.ai/keys"
    echo ""

    ask_secret "API key (sk-or-...)"
    PROVIDER_API_KEY="$REPLY"
    [ -z "$PROVIDER_API_KEY" ] && die "API key is required"

    echo ""
    info "Popular models:"
    echo "    google/gemma-3-1b-it          (free)"
    echo "    qwen/qwen3-0.6b              (cheap)"
    echo "    google/gemini-2.0-flash       (fast)"
    echo "    anthropic/claude-sonnet-4.5   (powerful)"
    echo ""

    ask "Model ID" "google/gemma-3-1b-it"
    local or_model="$REPLY"

    ask "Friendly name for this model" "$(echo "$or_model" | sed 's|.*/||; s|[^a-zA-Z0-9]|-|g')"
    PROVIDER_MODEL_NAME="$REPLY"

    PROVIDER_MODEL="openrouter/${or_model}"
    PROVIDER_API_BASE="https://openrouter.ai/api/v1"
    PROVIDER_TIMEOUT=120
    PROVIDER_MAX_TOKENS=4096

    info "Verifying API key..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
        "${PROVIDER_API_BASE}/models" 2>/dev/null || echo "000")
    if [ "$status" = "200" ]; then
        ok "API key is valid"
    else
        warn "Could not verify API key (HTTP ${status}) — continuing anyway"
    fi
}

# ── Telegram onboarding ────────────────────────────────────────────

TELEGRAM_ENABLED="false"
TELEGRAM_TOKEN=""
TELEGRAM_ALLOW_FROM="[]"

onboard_telegram() {
    echo ""
    echo "  ── Telegram Bot ──────────────────────────"
    echo ""

    if ! ask_yn "  Enable Telegram bot?" "n"; then
        info "Telegram disabled"
        return
    fi

    TELEGRAM_ENABLED="true"

    echo ""
    info "Create a bot via @BotFather on Telegram to get your token."
    echo "  1. Open @BotFather in Telegram"
    echo "  2. Send /newbot and follow the prompts"
    echo "  3. Copy the token it gives you"
    echo ""

    ask_secret "Bot token (123456:ABC...)"
    TELEGRAM_TOKEN="$REPLY"
    [ -z "$TELEGRAM_TOKEN" ] && die "Bot token is required"

    # Verify token
    info "Verifying bot token..."
    local bot_info
    bot_info=$(curl -sf "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getMe" 2>/dev/null || echo "")
    if echo "$bot_info" | grep -q '"ok":true'; then
        local bot_name
        bot_name=$(echo "$bot_info" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
        ok "Bot verified: @${bot_name}"
    else
        warn "Could not verify token — continuing anyway"
    fi

    echo ""
    info "To find your Telegram user ID:"
    echo "  1. Open @userinfobot in Telegram"
    echo "  2. Send /start — it will reply with your ID"
    echo ""
    echo "  Enter user IDs that can talk to the bot."
    echo "  Comma-separated for multiple, or leave blank to allow everyone."
    echo ""

    ask "Allowed user IDs" ""
    if [ -n "$REPLY" ]; then
        # Convert "123,456,789" to ["123","456","789"]
        TELEGRAM_ALLOW_FROM="[$(echo "$REPLY" | sed 's/[[:space:]]//g; s/,/","/g; s/.*/"&"/')]"
    else
        TELEGRAM_ALLOW_FROM="[]"
        warn "No user filter — anyone can message your bot"
    fi

    echo ""

    # Disable group pairing — respond immediately
    info "Bot will respond to direct messages immediately (no pairing required)."

    ok "Telegram configured"
}

# ── Install PicoClaw binary ─────────────────────────────────────────

install_picoclaw() {
    local os arch
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

    if command -v picoclaw >/dev/null 2>&1; then
        ok "PicoClaw already installed"
        return
    fi

    info "Downloading PicoClaw ${PICOCLAW_VERSION} (${OS}/${ARCH})..."
    local archive="picoclaw_${OS}_${ARCH}.tar.gz"
    local url="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/${archive}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    curl -fSL --progress-bar "$url" -o "${tmpdir}/${archive}"
    tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"

    local binary="${tmpdir}/picoclaw"
    if [ ! -f "$binary" ]; then
        binary="$(find "$tmpdir" -name picoclaw -type f | head -1)"
        [ -z "$binary" ] && die "Could not find picoclaw binary"
    fi

    mkdir -p "$INSTALL_DIR"
    mv "$binary" "${INSTALL_DIR}/picoclaw"
    chmod +x "${INSTALL_DIR}/picoclaw"
    rm -rf "$tmpdir"
    ok "PicoClaw installed to ${INSTALL_DIR}/picoclaw"
}

# ── Write config ────────────────────────────────────────────────────

write_config() {
    local config_file="${PICOCLAW_HOME}/config.json"
    mkdir -p "$PICOCLAW_HOME" "${PICOCLAW_HOME}/workspace"

    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak"
        warn "Backed up existing config to config.json.bak"
    fi

    cat > "$config_file" <<CONF
{
  "agents": {
    "defaults": {
      "workspace": "~/.picoclaw/workspace",
      "restrict_to_workspace": true,
      "model_name": "${PROVIDER_MODEL_NAME}",
      "max_tokens": ${PROVIDER_MAX_TOKENS},
      "temperature": 0.7,
      "max_tool_iterations": 5,
      "summarize_message_threshold": 20,
      "summarize_token_percent": 75
    }
  },
  "model_list": [
    {
      "model_name": "${PROVIDER_MODEL_NAME}",
      "model": "${PROVIDER_MODEL}",
      "api_key": "${PROVIDER_API_KEY}",
      "api_base": "${PROVIDER_API_BASE}",
      "request_timeout": ${PROVIDER_TIMEOUT}
    }
  ],
  "channels": {
    "telegram": {
      "enabled": ${TELEGRAM_ENABLED},
      "token": "${TELEGRAM_TOKEN}",
      "base_url": "",
      "proxy": "",
      "allow_from": ${TELEGRAM_ALLOW_FROM},
      "group_trigger": {
        "mention_only": true
      },
      "typing": {
        "enabled": true
      }
    }
  },
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

# ── Ensure PATH ─────────────────────────────────────────────────────

ensure_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) return ;;
    esac

    local shell_rc="$HOME/.bashrc"
    [ "$(basename "${SHELL:-bash}")" = "zsh" ] && shell_rc="$HOME/.zshrc"
    if [ -f "$shell_rc" ]; then
        printf '\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$shell_rc"
        info "Added to PATH in ${shell_rc} — run: source ${shell_rc}"
    fi
}

# ── Main ────────────────────────────────────────────────────────────

main() {
    onboard_provider
    onboard_telegram
    echo ""
    install_picoclaw
    write_config
    ensure_path

    echo ""
    echo "  ────────────────────────────────────────────"
    ok "Ready!"
    echo ""
    echo "    picoclaw agent            # interactive CLI chat"
    echo "    picoclaw agent -m 'hi'    # one-shot query"
    if [ "$TELEGRAM_ENABLED" = "true" ]; then
        echo ""
        echo "    picoclaw gateway          # start Telegram bot"
    fi
    echo ""
    info "Config:  ${PICOCLAW_HOME}/config.json"
    info "Model:   ${PROVIDER_MODEL}"
    echo ""
}

main "$@"
