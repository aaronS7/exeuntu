IMAGE ?= exeuntu-codex:latest
HERDR_API_REPOSITORY ?= aaronS7/herdr-api
HERDR_API_VERSION ?= latest

.PHONY: default build-exeuntu build run run-bash test

default: build-exeuntu

build-exeuntu: ## Build the Codex-only exeuntu Docker image locally
	@echo "Building $(IMAGE)..."
	@set -eu; \
	herdr_api_repository="$(HERDR_API_REPOSITORY)"; \
	if ! printf '%s\n' "$${herdr_api_repository}" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$$'; then \
		echo "Invalid Herdr API release repository: $${herdr_api_repository}" >&2; \
		exit 1; \
	fi; \
	herdr_api_version="$(HERDR_API_VERSION)"; \
	if [ "$${herdr_api_version}" = latest ]; then \
		herdr_api_release_url="$$(curl -fsSLI --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
			-o /dev/null -w '%{url_effective}' "https://github.com/$${herdr_api_repository}/releases/latest")"; \
		herdr_api_release_ref="$${herdr_api_release_url##*/}"; \
		herdr_api_version="$${herdr_api_release_ref#v}"; \
	else \
		herdr_api_version="$${herdr_api_version#v}"; \
	fi; \
	if ! printf '%s\n' "$${herdr_api_version}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$$'; then \
		echo "Invalid Herdr API release version: $${herdr_api_version}" >&2; \
		exit 1; \
	fi; \
	bun_release_url="$$(curl -fsSLI --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
		-o /dev/null -w '%{url_effective}' https://github.com/oven-sh/bun/releases/latest)"; \
	bun_release_ref="$${bun_release_url##*/}"; \
	herdr_version="$$(curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
		https://herdr.dev/latest.json | jq -r '.version')"; \
	collie_release_url="$$(curl -fsSLI --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
		-o /dev/null -w '%{url_effective}' https://github.com/AltanS/collie/releases/latest)"; \
	collie_release_ref="$${collie_release_url##*/}"; \
	case "$${bun_release_ref}" in bun-v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "Invalid Bun release: $${bun_release_ref}" >&2; exit 1 ;; esac; \
	case "$${herdr_version}" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "Invalid Herdr release: $${herdr_version}" >&2; exit 1 ;; esac; \
	case "$${collie_release_ref}" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "Invalid Collie release: $${collie_release_ref}" >&2; exit 1 ;; esac; \
	herdr_toolchain_cache_key="$${bun_release_ref}-$${herdr_version}-$${collie_release_ref}"; \
	docker build \
		--build-arg HERDR_API_REPOSITORY="$${herdr_api_repository}" \
		--build-arg HERDR_API_VERSION="$${herdr_api_version}" \
		--build-arg HERDR_TOOLCHAIN_CACHE_KEY="$${herdr_toolchain_cache_key}" \
		-t "$(IMAGE)" .
	@echo "✓ Image built locally as $(IMAGE)"

build: build-exeuntu

test:
	cd cli && go test ./...
	bash -n exeuntu-install init-wrapper.sh motd-snippet.bash

run: build-exeuntu
	docker run -it \
	  --cap-add=ALL \
	  --security-opt seccomp=unconfined \
	  --security-opt apparmor=unconfined \
	  --cgroupns private \
	  --tmpfs /run \
	  --tmpfs /run/lock \
	  --tmpfs /tmp \
	  --tmpfs /sys/fs/cgroup:rw \
	  $(IMAGE)

run-bash: build-exeuntu
	docker run -it \
	  --cap-add=ALL \
	  --security-opt seccomp=unconfined \
	  --security-opt apparmor=unconfined \
	  --cgroupns private \
	  --tmpfs /run \
	  --tmpfs /run/lock \
	  --tmpfs /tmp \
	  --tmpfs /sys/fs/cgroup:rw \
	  $(IMAGE) bash
