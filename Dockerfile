# syntax=docker/dockerfile:1.7

# Stage 1: Get Chrome/Chromium from chromedp/headless-shell
FROM docker.io/chromedp/headless-shell:stable AS chrome

# Build the guest-facing exeuntu helper.
FROM docker.io/library/golang:1.26.5 AS exeuntu-cli
ARG EXEUNTU_GIT_VERSION=unknown
WORKDIR /src/exeuntu-cli
COPY cli/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -mod=mod -tags osusergo,netgo \
        -ldflags "-X main.gitVersion=${EXEUNTU_GIT_VERSION} -extldflags=-static -s -w" \
        -o /out/exeuntu .

# Build Herdr API from its private GitHub repository. The GitHub credential is
# supplied as a BuildKit secret and is never copied into a layer or final image.
FROM docker.io/library/rust:1-bookworm AS herdr-api-builder
ARG HERDR_API_REPOSITORY=https://github.com/aaronS7/herdr-api.git
ARG HERDR_API_REF=main
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates git && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src/herdr-api
RUN --mount=type=secret,id=herdr_api_github_token,required=false \
    git init . && \
    git remote add origin "${HERDR_API_REPOSITORY}" && \
    case "${HERDR_API_REPOSITORY}" in \
        https://github.com/*) \
            if [ -s /run/secrets/herdr_api_github_token ]; then \
                GIT_TERMINAL_PROMPT=0 git \
                  -c 'credential.helper=!f() { printf "%s\n" "username=x-access-token" "password=$(cat /run/secrets/herdr_api_github_token)"; }; f' \
                  fetch --depth 1 origin "${HERDR_API_REF}"; \
            else \
                GIT_TERMINAL_PROMPT=0 git fetch --depth 1 origin "${HERDR_API_REF}"; \
            fi \
            ;; \
        https://github.int.exe.xyz/*) \
            GIT_TERMINAL_PROMPT=0 git fetch --depth 1 origin "${HERDR_API_REF}" \
            ;; \
        *) \
            echo "HERDR_API_REPOSITORY must use github.com or the documented exe.dev GitHub integration host" >&2; \
            exit 1 \
            ;; \
    esac && \
    git checkout --detach FETCH_HEAD && \
    rm -rf .git && \
    cargo build --locked --release && \
    install -Dm0755 target/release/herdr-api /out/herdr-api && \
    printf '%s\n' "${HERDR_API_REF}" > /out/herdr-api-revision

FROM ubuntu:24.04

# Switch from dash to bash by default.
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]


# Remove minimization restrictions and install packages with documentation
# We aim for a usable non-minimal system.
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirror://mirrors.ubuntu.com/mirrors.txt|' /etc/apt/sources.list && \
        rm -f /etc/dpkg/dpkg.cfg.d/excludes /etc/dpkg/dpkg.cfg.d/01_nodoc && \
	apt-get update && \
	# Pull in all available security/bugfix updates for packages already
	# in the base ubuntu:24.04 image. Without this we ship whatever was
	# current when Canonical last rebuilt the base layer, which can be
	# months behind (e.g. nginx Rift, CVE-2026-42945). The weekly cron
	# rebuild + no-cache will keep this fresh going forward.
	DEBIAN_FRONTEND=noninteractive apt-get -y \
		-o Dpkg::Options::=--force-confold \
		-o Dpkg::Options::=--force-confdef \
		dist-upgrade && \
	# Pre-configure debconf to avoid interactive prompts
	echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
	# Pre-configure pbuilder to avoid mirror prompt
	echo 'pbuilder pbuilder/mirrorsite string http://archive.ubuntu.com/ubuntu' | debconf-set-selections && \
	# Run unminimize with single 'y' response to restore documentation
	echo 'y' | DEBIAN_FRONTEND=noninteractive unminimize && \
	# Install man-db and reinstall all base packages to get their man pages back
	DEBIAN_FRONTEND=noninteractive apt-get install -y man-db && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall $(dpkg-query -f '${binary:Package} ' -W) && \
	mandb -c && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		ca-certificates wget ripgrep \
		locales locales-all \
		git jq sqlite3 curl vim neovim lsof iproute2 less nginx \
		make python3-pip python-is-python3 tree net-tools file build-essential \
		pipx psmisc bsdmainutils sudo socat \
		openssh-server openssh-client \
		libcap2-bin unzip util-linux rsync \
		iputils-ping socat netcat-openbsd \
		ubuntu-server ubuntu-dev-tools ubuntu-standard \
		man-db manpages manpages-dev \
		mitmproxy \
		systemd systemd-sysv \
		atop btop iotop ncdu \
		git \
		libglib2.0-0 libnss3 libx11-6 libxcomposite1 libxdamage1 \
		libxext6 libxi6 libxrandr2 libgbm1 libgtk-3-0 \
		fonts-noto-color-emoji fonts-symbola \
		docker.io docker-buildx docker-compose-v2 \
		imagemagick ffmpeg \
		bubblewrap \
		gh \
		dbus-user-session \
		&& apt-get remove -y pollinate ubuntu-fan && \
		# openssh-server generates host keys during package configuration.
		# Do not bake those per-image private keys into exeuntu.
		rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub && \
		# Allow non-root users to use ping without sudo by granting CAP_NET_RAW
		setcap cap_net_raw=+ep /usr/bin/ping && \
	fc-cache -f -v && \
	# Remove policy-rc.d so services can start normally (the base image includes this
	# to prevent services from starting during build, but we run systemd at runtime)
	rm -f /usr/sbin/policy-rc.d

# Install Tailscale (keyring method, per https://tailscale.com/install.sh)
# This must run after ca-certificates and curl are installed.
RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale

# Install latest stable Go from go.dev (the golang-go apt package lags behind)
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version') && \
    curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xzC /usr/local && \
    ln -s /usr/local/go/bin/go /usr/local/bin/go && \
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

COPY --from=exeuntu-cli /out/exeuntu /usr/local/bin/exeuntu

# Install uv to /usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Configure systemd
RUN rm /etc/systemd/system/multi-user.target.wants/console-setup.service \
		/etc/systemd/system/multi-user.target.wants/ModemManager.service \
		/etc/systemd/system/multi-user.target.wants/snapd.* \
		/etc/systemd/system/multi-user.target.wants/unattended-upgrades.* \
		/etc/systemd/system/multi-user.target.wants/ubuntu-advantage.service && \
	systemctl mask -- getty.target \
		fwupd.service \
		fwupd-refresh.service \
		fwupd-refresh.timer \
		systemd-random-seed.service \
		iscsid.socket \
		dm-event.socket \
		man-db.timer \
		update-notifier-download.timer \
		update-notifier-motd.timer \
		atop-rotate.timer \
		dpkg-db-backup.timer \
		e2scrub_all.timer \
		etc-resolv.conf.mount \
		etc-hosts.mount \
		etc-hostname.mount \
		-.mount \
		systemd-resolved.service \
		systemd-remount-fs.service \
		systemd-sysusers.service \
		systemd-update-done.service \
		systemd-update-utmp.service \
		systemd-journal-catalog-update.service \
		modprobe@.service \
		systemd-modules-load.service \
		systemd-udevd.service \
		systemd-udevd-control.service \
		systemd-udevd-kernel.service \
		systemd-udev-trigger.service \
		systemd-udev-settle.service \
		systemd-hwdb-update.service \
		ubuntu-fan.service \
		ldconfig.service \
		unattended-upgrades.service \
		lxd-installer.socket \
	        console-getty.service \
		keyboard-setup.service \
		systemd-ask-password-console.path \
		systemd-ask-password-wall.path \
		ssh.socket \
		ssh.service \
		plymouth.service \
		plymouth-start.service \
		plymouth-quit.service \
		plymouth-quit-wait.service \
		plymouth-read-write.service \
		plymouth-switch-root.service \
		plymouth-switch-root-initramfs.service \
		plymouth-halt.service \
		plymouth-reboot.service \
		plymouth-poweroff.service \
		plymouth-kexec.service \
		apt-daily-upgrade.timer \
		apt-daily.timer \
		plymouth-log.service && \
	# systemd-logind is disabled but not masked. It's involved in populating the XDG runtime dir sockets... somehow
	systemctl disable docker.service containerd.service getty.target systemd-logind.service tailscaled.service \
		nginx.service \
                   console-getty.service \
		   atop.service \
                   getty@.service \
                   snapd.socket \
		   motd-news.timer motd-news.service \
		    apport.service apport-autoreport.timer apport-autoreport.path apport-forward.socket \
		    snapd.snap-repair.timer snapd.snap-repair.service \
		    udisks2.service \
		   ufw.service \
		   lvm2-lvmpolld.socket \
                   systemd-ask-password-wall.service \
                   systemd-ask-password-console.service \
                   systemd-machine-id-commit.service \
                   systemd-modules-load.service \
                   systemd-sysctl.service \
                   systemd-firstboot.service \
                   systemd-udevd.service \
                   systemd-udev-trigger.service \
                   systemd-udev-settle.service \
		   e2scrub_reap.service \
		   systemd-update-utmp.service \
		   atopacct.service \
		   sysstat.service \
                   systemd-hwdb-update.service \
		   multipathd.service && \
	mkdir -p /etc/systemd/system.conf.d && \
    		echo '[Manager]' > /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'LogLevel=info' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'LogTarget=console' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'SystemCallArchitectures=native' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'DefaultOOMPolicy=continue' >> /etc/systemd/system.conf.d/container-overrides.conf && \
	mkdir -p /etc/systemd/journald.conf.d && \
		echo '[Journal]' > /etc/systemd/journald.conf.d/persistent.conf && \
		echo 'Storage=persistent' >> /etc/systemd/journald.conf.d/persistent.conf && \
	systemctl set-default multi-user.target

# Modify existing ubuntu user (UID 1000) to become exedev user
RUN usermod -l exedev -c "exe.dev user" ubuntu && \
	groupmod -n exedev ubuntu && \
	mv /home/ubuntu /home/exedev && \
	usermod -d /home/exedev exedev && \
	usermod -aG sudo exedev && \
	usermod -aG docker exedev && \
	sed -i 's/^ubuntu:/exedev:/' /etc/subuid /etc/subgid && \
	echo 'exedev ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
	echo 'Defaults:exedev verifypw=any' >> /etc/sudoers && \
	# Manually enable linger, this should autopopulate /run/user/1000
	mkdir -p /var/lib/systemd/linger && \
	touch /var/lib/systemd/linger/exedev

# Bake /etc/fstab so systemd-growfs@-.service resizes the root filesystem on
# first boot after the disk is grown.
RUN echo '/dev/vda / ext4 defaults,x-systemd.growfs 0 1' > /etc/fstab

# Stop systemd wiping /tmp at boot; that races non-systemd users of the system
# that also run at boot.
COPY tmpfiles-tmp.conf /etc/tmpfiles.d/tmp.conf

ENV EXEUNTU=1

# https://github.com/trfore/docker-ubuntu2404-systemd/blob/main/Dockerfile suggests the following
# might be useful?
# STOPSIGNAL SIGRTMIN+3


# Copy the self-contained Chrome bundle from chromedp/headless-shell
COPY --from=chrome /headless-shell /headless-shell
ENV PATH="/usr/local/bin:/headless-shell:${PATH}"

RUN mkdir -p /home/exedev /home/exedev/.config/shelley && \
    chown exedev:exedev /home/exedev /home/exedev/.config /home/exedev/.config/shelley

USER exedev

WORKDIR /home/exedev

# Update PATH in .bashrc to include .local/bin and set XDG_RUNTIME_DIR for systemd user services
# XDG paths are not autopopulated despite the presense of libpam-systemd. Manually add them here.
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.profile

# Configure git to use 'main' as default branch name
RUN git config --global init.defaultBranch main

# Switch back to root to install systemd service
USER root

# Disable Ubuntu's default MOTD (the sudo hint, etc.)
RUN rm -rf /etc/update-motd.d/* /etc/motd && touch /home/exedev/.hushlogin && chown exedev:exedev /home/exedev/.hushlogin

# Add custom MOTD to exedev's .bashrc (ignores .hushlogin - we handle that ourselves)
COPY motd-snippet.bash /tmp/motd-snippet.bash
RUN cat /tmp/motd-snippet.bash >> /home/exedev/.bashrc && rm /tmp/motd-snippet.bash

# Create systemd socket and service for Shelley (socket activation).
# The shelley binary itself is installed at vm creation.
COPY shelley.socket /etc/systemd/system/shelley.socket
COPY shelley.service /etc/systemd/system/shelley.service
RUN chmod 644 /etc/systemd/system/shelley.socket /etc/systemd/system/shelley.service && \
    systemctl enable shelley.socket

# Create systemd oneshot service for /exe.dev/setup script
COPY exe-setup.service /etc/systemd/system/exe-setup.service
RUN chmod 644 /etc/systemd/system/exe-setup.service && \
    systemctl enable exe-setup.service

# TODO(crawshaw/philip): This is called init so that exetini decides
# this wrapper script is an init, and exec's it rather than forking it.
# It would be better if you could indicate that via an env variable or something.
COPY init-wrapper.sh /usr/local/bin/init

# Create config directories for LLM agents
RUN mkdir -p /home/exedev/.claude /home/exedev/.codex /home/exedev/.pi && \
    chown -R exedev:exedev /home/exedev/.claude /home/exedev/.codex /home/exedev/.pi

# Copy LLM agent instructions to Claude, Codex, and Shelley config directories
# Shelley uses ~/.config/shelley/ (XDG convention, directory already created above)
COPY AGENTS.md /home/exedev/.config/shelley/AGENTS.md
RUN chown exedev:exedev /home/exedev/.config/shelley/AGENTS.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.claude/CLAUDE.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.codex/AGENTS.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.pi/AGENTS.md

# Install Claude and Codex through exeuntu's direct updaters.
USER root
RUN exeuntu update claude && \
    test -x /usr/local/bin/claude && \
    /usr/local/bin/claude --version
RUN exeuntu update codex && \
    test -x /usr/local/bin/codex && \
    /usr/local/bin/codex --version

# Install pi (pi-coding-agent) through exeuntu's updater.
ARG PI_VERSION=
USER exedev
RUN if [ -n "${PI_VERSION}" ]; then \
        exeuntu update pi --home /home/exedev --version "${PI_VERSION}"; \
    else \
        exeuntu update pi --home /home/exedev; \
    fi && \
    test -x /home/exedev/.local/bin/pi && \
    /home/exedev/.local/bin/pi --version

# Install Bun (required to build Collie), the latest stable Herdr, and the
# latest stable Collie release. Make passes their published versions as a cache
# key so a newly published release invalidates this layer.
ARG HERDR_TOOLCHAIN_CACHE_KEY=auto
RUN test -n "${HERDR_TOOLCHAIN_CACHE_KEY}" && \
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 120 \
      https://bun.sh/install | env BUN_INSTALL=/home/exedev/.local bash && \
    test -x /home/exedev/.local/bin/bun && \
    /home/exedev/.local/bin/bun --version
RUN curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
      https://herdr.dev/install.sh | env HERDR_INSTALL_DIR=/home/exedev/.local/bin sh && \
    test -x /home/exedev/.local/bin/herdr && \
    HERDR_LATEST_VERSION=$(curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
      https://herdr.dev/latest.json | jq -r '.version') && \
    test "$(/home/exedev/.local/bin/herdr --version)" = "herdr ${HERDR_LATEST_VERSION}"
RUN COLLIE_RELEASE_URL=$(curl -fsSLI --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
      -o /dev/null -w '%{url_effective}' https://github.com/AltanS/collie/releases/latest) && \
    COLLIE_RELEASE_REF=${COLLIE_RELEASE_URL##*/} && \
    [[ "${COLLIE_RELEASE_REF}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
    /home/exedev/.local/bin/herdr plugin install AltanS/collie \
      --ref "${COLLIE_RELEASE_REF}" --yes && \
    test "$(/home/exedev/.local/bin/herdr plugin list --plugin herdr.collie --json | \
      jq -r '.result.plugins[0].version')" = "${COLLIE_RELEASE_REF#v}"
USER root
RUN ln -sf /home/exedev/.local/bin/pi /usr/local/bin/pi && \
    ln -sf /home/exedev/.local/bin/bun /usr/local/bin/bun && \
    ln -sf /home/exedev/.local/bin/herdr /usr/local/bin/herdr

# Install the pi exe.dev extension (LLM integration + environment context).
# The bundled public catalog supplies pricing and compatibility metadata only;
# reflection-discovered integrations supply every model and provider route.
COPY pi-extension/ /home/exedev/.pi/agent/extensions/exe-dev/
RUN curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
      https://exe.dev/llm-gateway-models.json \
      -o /home/exedev/.pi/agent/extensions/exe-dev/catalog.json && \
    jq -e '.schemaVersion | numbers' \
      /home/exedev/.pi/agent/extensions/exe-dev/catalog.json > /dev/null
RUN chown -R exedev:exedev /home/exedev/.pi/agent

# Pre-install fd at the path pi checks first (~/.pi/agent/bin/fd), so pi
# doesn't try (and on a fresh VM, often fail with a GitHub API 403) to
# download it on first use.
RUN ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) FD_ARCH="x86_64-unknown-linux-gnu" ;; \
        aarch64|arm64) FD_ARCH="aarch64-unknown-linux-gnu" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    FD_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/sharkdp/fd/releases/latest | sed 's|.*/tag/||') && \
    mkdir -p /home/exedev/.pi/agent/bin && \
    TMPDIR=$(mktemp -d) && \
    curl -fsSL "https://github.com/sharkdp/fd/releases/download/${FD_VERSION}/fd-${FD_VERSION}-${FD_ARCH}.tar.gz" | \
        tar -xz -C "${TMPDIR}" && \
    mv "${TMPDIR}/fd-${FD_VERSION}-${FD_ARCH}/fd" /home/exedev/.pi/agent/bin/fd && \
    rm -rf "${TMPDIR}" && \
    chmod 0755 /home/exedev/.pi/agent/bin/fd && \
    chown -R exedev:exedev /home/exedev/.pi/agent/bin

# Custom nginx config and index page (nginx is installed but disabled by default)
COPY nginx.conf /etc/nginx/sites-available/default
COPY index.html /var/www/html/index.html
RUN chmod 644 /var/www/html/index.html

# Install xterm-ghostty terminfo for Ghostty terminal support
COPY xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN tic -x - < /tmp/xterm-ghostty.terminfo && rm /tmp/xterm-ghostty.terminfo

# Install Herdr API and start it with the user's systemd manager. Its separate
# config unit generates a per-VM bearer token at first boot; no runtime or
# GitHub secret is baked into the image.
COPY --from=herdr-api-builder /out/herdr-api /usr/local/bin/herdr-api
COPY --from=herdr-api-builder /out/herdr-api-revision /usr/local/share/herdr-api/revision
COPY herdr-api-init /usr/local/libexec/herdr-api-init
COPY herdr-api-config.service /etc/systemd/user/herdr-api-config.service
COPY herdr-api.service /etc/systemd/user/herdr-api.service
RUN chmod 0755 /usr/local/libexec/herdr-api-init && \
    chmod 0644 /etc/systemd/user/herdr-api-config.service \
        /etc/systemd/user/herdr-api.service && \
    systemctl --global enable herdr-api.service

# Expose the web server ports
EXPOSE 8000 9999

LABEL "exe.dev/login-user"="exedev"
LABEL "exe.dev/install-shelley"="true"
CMD ["/usr/local/bin/init"]
