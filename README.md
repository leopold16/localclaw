# localclaw

One-command install of [PicoClaw](https://github.com/sipeed/picoclaw) + [Qwen3 0.6B](https://ollama.com/library/qwen3:0.6b) running locally via Ollama. Supports tool calling, optimized for CPU with 2K context window.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/leopold16/localclaw/main/install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/leopold16/localclaw.git && bash localclaw/install.sh
```

## What it does

1. Installs [Ollama](https://ollama.com) (or checks existing >= 0.6)
2. Pulls `qwen3:0.6b` and creates a `localclaw` model variant (2K context for fast CPU inference)
3. Downloads [PicoClaw](https://github.com/sipeed/picoclaw) binary
4. Wires config to the local model

## Usage

```bash
picoclaw agent            # interactive chat
picoclaw agent -m 'hello' # one-shot
```

Config lives at `~/.picoclaw/config.json`.

## EC2 quickstart

```bash
# Ubuntu, t3.medium (4 GB RAM), 16 GB EBS
ssh ubuntu@<ip>
curl -fsSL https://raw.githubusercontent.com/leopold16/localclaw/main/install.sh | bash
source ~/.bashrc
picoclaw agent
```
