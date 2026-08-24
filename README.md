# exeuntu

exeuntu is available at http://ghcr.io/boldsoftware/exeuntu

exeuntu is the default base image for [exe.dev](https://exe.dev/). It is kitted-out
for developers, based on ubuntu24.04, and includes systemd.

We believe that minimal containers make for terrible developer (and agent)
experiences, so exeuntu includes a lot of stuff, mostly from apt.

You can build exeuntu with Docker, but running it, including systemd,
is difficult with Docker.

## Building this fork

This fork installs the latest stable Bun, Herdr, and Collie releases and builds
Herdr API from `aaronS7/herdr-api`. `make` resolves the published versions and
API commit before building, so Docker invalidates the relevant cached layers
when an update exists. The API repository may remain private: its GitHub
credential is forwarded as a Docker BuildKit secret. The build uses
`HERDR_API_GITHUB_TOKEN`, `GH_TOKEN`, or the credential returned by
`gh auth token`, in that order.

Keeping the source repository private does not hide the compiled binary from
people who can pull the resulting image. Publish the image privately too if
the API implementation is proprietary.

```bash
make
```

On an exe.dev VM with a read-only GitHub integration attached to the private
repository, no token needs to be forwarded:

```bash
HERDR_API_REPOSITORY=https://github.int.exe.xyz/aaronS7/herdr-api.git make
```

Herdr API starts as a user service. On first boot it creates
`~/.config/herdr-api.env` with mode `0600` and listens on
`127.0.0.1:8788`; port `8787` remains available for Collie. Keep the API on
loopback and reach it through SSH, a private network, or a TLS reverse proxy.

Collie's own `start` action creates and enables its persistent user service.
Run it once on a new VM to make Collie survive later boots (user lingering is
already enabled in this image):

```bash
herdr plugin action invoke start --plugin herdr.collie
```
