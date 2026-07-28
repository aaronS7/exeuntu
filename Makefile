IMAGE ?= exeuntu-codex:latest

.PHONY: default build-exeuntu build run run-bash test

default: build-exeuntu

build-exeuntu: ## Build the Codex-only exeuntu Docker image locally
	@echo "Building $(IMAGE)..."
	docker build -t $(IMAGE) .
	@echo "✓ Image built locally as $(IMAGE)"

build: build-exeuntu

test:
	cd cli && go test ./...

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
