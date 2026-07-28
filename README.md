# exeuntu — Codex-only variant

A focused exeuntu image for developers who use Codex as their coding agent.
It remains based on Ubuntu 24.04 and retains systemd, Tailscale, Herdr, common
command-line development tools, the exe.dev setup service, and Codex
LLM-integration configuration.

This branch removes the bundled Claude Code, Pi, and Shelley agents, along with
Pi's exe.dev extension and Shelley's headless Chromium runtime. It also omits the
large Ubuntu metapackages, Docker, Go, all-locales bundle, restored documentation,
and Python-heavy utilities from the default image.

## Build

```sh
make
```

The default local image name is `exeuntu-codex:latest`. Override it when building
for your own registry:

```sh
make IMAGE=ghcr.io/OWNER/exeuntu-codex:latest
```

## Public container image

A multi-architecture image for Linux AMD64 and ARM64 is published to GitHub
Container Registry:

```sh
docker pull ghcr.io/aarons7/exeuntu-slim-codex:latest
```

## Optional toolsets

The `exeuntu-install` command restores omitted capabilities on demand:

```sh
sudo exeuntu-install docker
sudo exeuntu-install go
sudo exeuntu-install go 1.26.5
sudo exeuntu-install locales-all
sudo exeuntu-install ubuntu-full
sudo exeuntu-install python-tools
sudo exeuntu-install docs
```

The default locale is `en_US.UTF-8`. The `docs` toolset removes Ubuntu's package
documentation exclusions, installs man pages, and reinstalls existing packages so
documentation omitted from the base image is restored.

## Test

```sh
make test
```
