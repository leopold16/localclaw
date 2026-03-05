# localclaw

One-command install of [PicoClaw](https://github.com/sipeed/picoclaw) + [Gemma 3 1B](https://ollama.com/library/gemma3:1b) running locally via Ollama.

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
2. Pulls `gemma3:1b` (~815 MB)
3. Downloads [PicoClaw](https://github.com/sipeed/picoclaw) binary
4. Wires config to use the local model

## Usage

```bash
picoclaw agent            # interactive chat
picoclaw agent -m 'hello' # one-shot
```

Config lives at `~/.picoclaw/config.json`.

## EC2 quickstart

```bash
# spin up an instance (Ubuntu, t3.medium or larger), then:
ssh ec2-user@<ip>
curl -fsSL https://raw.githubusercontent.com/leopold16/localclaw/main/install.sh | bash
source ~/.bashrc
picoclaw agent
```
