IMAGE ?= exeuntu-codex:latest
HERDR_API_REPOSITORY ?= https://github.com/aaronS7/herdr-api.git
HERDR_API_REF ?= main

.PHONY: default build-exeuntu build run run-bash test

default: build-exeuntu

build-exeuntu: ## Build the Codex-only exeuntu Docker image locally
	@echo "Building $(IMAGE)..."
	@case "$(HERDR_API_REPOSITORY)" in \
		https://github.com/*) \
			herdr_api_github_token="$${HERDR_API_GITHUB_TOKEN:-$${GH_TOKEN:-$$(gh auth token 2>/dev/null || true)}}"; \
			if [ -n "$${herdr_api_github_token}" ]; then \
				export HERDR_API_GITHUB_TOKEN="$${herdr_api_github_token}"; \
				herdr_api_ref="$$(GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git \
					-c credential.helper= \
					-c 'credential.helper=!f() { printf "%s\n" "username=x-access-token" "password=$$HERDR_API_GITHUB_TOKEN"; }; f' \
					ls-remote "$(HERDR_API_REPOSITORY)" "$(HERDR_API_REF)" | awk 'NR == 1 { print $$1 }')"; \
				set -- --secret id=herdr_api_github_token,env=HERDR_API_GITHUB_TOKEN; \
			else \
				herdr_api_ref="$$(GIT_TERMINAL_PROMPT=0 git ls-remote \
					"$(HERDR_API_REPOSITORY)" "$(HERDR_API_REF)" 2>/dev/null | awk 'NR == 1 { print $$1 }')"; \
				set --; \
			fi \
			;; \
		https://github.int.exe.xyz/*) \
			herdr_api_ref="$$(GIT_TERMINAL_PROMPT=0 git ls-remote \
				"$(HERDR_API_REPOSITORY)" "$(HERDR_API_REF)" 2>/dev/null | awk 'NR == 1 { print $$1 }')"; \
			set -- \
			;; \
		*) \
			echo "HERDR_API_REPOSITORY must use github.com or the documented exe.dev GitHub integration host." >&2; \
			exit 1 \
			;; \
	esac; \
	if [ -z "$${herdr_api_ref}" ]; then \
		echo "Unable to resolve $(HERDR_API_REPOSITORY) at $(HERDR_API_REF)." >&2; \
		echo "Authenticate with gh, set HERDR_API_GITHUB_TOKEN, or use an attached exe.dev GitHub integration URL." >&2; \
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
	docker build "$$@" \
		--build-arg HERDR_API_REPOSITORY="$(HERDR_API_REPOSITORY)" \
		--build-arg HERDR_API_REF="$${herdr_api_ref}" \
		--build-arg HERDR_TOOLCHAIN_CACHE_KEY="$${herdr_toolchain_cache_key}" \
		-t "$(IMAGE)" .
	@echo "✓ Image built locally as $(IMAGE)"

build: build-exeuntu

test:
	cd cli && go test ./...
	bash -n exeuntu-install init-wrapper.sh motd-snippet.bash \
		scripts/setup-herdr-api-actions-secret

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
