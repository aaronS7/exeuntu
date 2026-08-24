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

## Herdr services

The image installs the latest stable Bun, Herdr, and Collie releases and builds
Herdr API from `aaronS7/herdr-api`. `make` resolves the published versions and
API commit before building so updated releases invalidate Docker's cached
layers. For the private API repository, it uses `HERDR_API_GITHUB_TOKEN`,
`GH_TOKEN`, or the credential returned by `gh auth token` as a BuildKit secret.

GitHub Actions needs a separate, read-only fine-grained token to fetch that
private repository. Configure it from an interactive terminal with:

```sh
./scripts/setup-herdr-api-actions-secret
```

The script opens (or prints) GitHub's prefilled token-creation page, asks you to
limit access to `aaronS7/herdr-api`, validates the token, and streams it directly
to the `HERDR_API_GITHUB_TOKEN` Actions secret in `aaronS7/exeuntu`. GitHub does
not provide an API that can approve personal access token creation, so generating
the token still requires one confirmation in the browser. The token is never
written to disk.

On an exe.dev VM with a read-only GitHub integration attached to that
repository, build without forwarding a token:

```sh
HERDR_API_REPOSITORY=https://github.int.exe.xyz/aaronS7/herdr-api.git make
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

Keeping the API source private does not hide its compiled binary from people
who can pull the image. Publish the image privately if the implementation is
proprietary.

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
