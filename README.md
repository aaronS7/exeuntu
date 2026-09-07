# exeuntu — Codex + Shelley variant

A focused exeuntu image for developers who use Codex and Shelley as coding agents.
It remains based on Ubuntu 24.04 and retains systemd, Tailscale, Herdr, common
command-line development tools, the exe.dev setup service, and Codex
LLM-integration configuration.

Shelley's socket-activated service, headless Chromium runtime, fonts, and media
tools are included. Claude Code, Pi, and Pi's exe.dev extension remain omitted,
as do the large Ubuntu metapackages, Docker, Go, all-locales bundle, restored
documentation, and Python-heavy utilities.

## Shelley

The `exe.dev/install-shelley=true` image label requests installation of the
Shelley binary when exe.dev creates a VM. The image enables `shelley.socket`,
which listens on `127.0.0.1:9999` and starts Shelley on the first connection.
Access Shelley through exe.dev's authenticated Shelley interface; the service
requires the proxy's `X-Exedev-Userid` header.

Shelley runs as `exedev`, stores its database and agent guidance in
`~/.config/shelley/`, and reads the exe.dev-provided `/exe.dev/shelley.json`.
The browser bundle is on both the service and interactive shell paths.
The binary and exe.dev configuration are not baked into the image, so running
this image with plain Docker alone does not start a usable Shelley instance.

Rebuild the image and create a new VM to receive these changes; existing VMs
are not modified by an image update. The branch and image names below remain
unchanged for compatibility.

## Build

```sh
make
```

The default local image name is `exeuntu-codex:latest`. Override it when building
for your own registry:

```sh
make IMAGE=ghcr.io/OWNER/exeuntu-codex:latest
```

## Herdr services

The image installs the latest stable Bun, Herdr, Collie, and Herdr API releases.
For Herdr API it downloads the static release binary matching the Docker target
architecture and verifies the published SHA-256 checksum instead of compiling
Rust under QEMU. `make` and the image publishing workflow resolve the latest
published versions so updated releases invalidate only the relevant Docker
layers.

Pin a particular Herdr API release for a local build with:

```sh
make HERDR_API_VERSION=0.1.0
```

Herdr API starts as a user service. On first boot it creates
`~/.config/herdr-api.env` with mode `0600` and listens on
`127.0.0.1:8788`; port `8787` remains available for Collie. Keep the API on
loopback and reach it through SSH, a private network, or a TLS reverse proxy.

Run Collie's start action once on a new VM to create and enable its persistent
user service:

```sh
herdr plugin action invoke start --plugin herdr.collie
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

Image builds also run `tests/shelley-image.bash` to check socket activation,
user-owned configuration, shared guidance, and the headless browser runtime.
