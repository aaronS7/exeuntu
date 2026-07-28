# exeuntu — Codex-only variant

A smaller exeuntu image for developers who use Codex as their coding agent.
It remains based on Ubuntu 24.04 and retains systemd, Docker, common development
tools, the exe.dev setup service, and Codex LLM-integration configuration.

This branch removes the bundled Claude Code, Pi, and Shelley agents, along with
Pi's exe.dev extension and Shelley's headless Chromium runtime.

## Build

```sh
make
```

The default local image name is `exeuntu-codex:latest`. Override it when building
for your own registry:

```sh
make IMAGE=ghcr.io/OWNER/exeuntu-codex:latest
```

## Test

```sh
make test
```

## Further size reductions

The image intentionally still contains much of upstream exeuntu's broad Ubuntu
developer toolset. A later package audit can remove documentation, desktop/media
libraries, Ubuntu metapackages, or language toolchains that your workloads do not
need.
