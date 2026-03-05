# localclaw

One-command install of [PicoClaw](https://github.com/sipeed/picoclaw) + [Qwen3 0.6B](https://huggingface.co/Mungert/Qwen3-0.6B-GGUF) running locally via Ollama. CPU-optimized Q4_0 quantization (~429 MB), supports tool calling.

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
2. Downloads [Qwen3-0.6B Q4_0 GGUF](https://huggingface.co/Mungert/Qwen3-0.6B-GGUF) (~429 MB, CPU-optimized)
3. Creates a custom Ollama model with 2K context for fast inference
4. Downloads [PicoClaw](https://github.com/sipeed/picoclaw) binary
5. Wires config to use the local model

## Usage

```bash
picoclaw agent            # interactive chat
picoclaw agent -m 'hello' # one-shot
```

Config lives at `~/.picoclaw/config.json`.

## EC2 quickstart

```bash
# Ubuntu, t3.medium or larger
ssh ec2-user@<ip>
curl -fsSL https://raw.githubusercontent.com/leopold16/localclaw/main/install.sh | bash
source ~/.bashrc
picoclaw agent
```
