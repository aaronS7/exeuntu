# syntax=docker/dockerfile:1.7

# Build the guest-facing exeuntu helper.
FROM docker.io/library/golang:1.26.5 AS exeuntu-cli
ARG EXEUNTU_GIT_VERSION=unknown
WORKDIR /src/exeuntu-cli
COPY cli/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -mod=mod -tags osusergo,netgo \
        -ldflags "-X main.gitVersion=${EXEUNTU_GIT_VERSION} -extldflags=-static -s -w" \
        -o /out/exeuntu .

FROM ubuntu:24.04

# Switch from dash to bash by default.
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]


# Install the focused base toolset. Ubuntu's documentation exclusions remain in
# place; `exeuntu-install docs` can restore the full interactive documentation.
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirror://mirrors.ubuntu.com/mirrors.txt|' /etc/apt/sources.list && \
	apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get -y \
		-o Dpkg::Options::=--force-confold \
		-o Dpkg::Options::=--force-confdef \
		dist-upgrade && \
	echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		ca-certificates wget ripgrep \
		locales \
		git gh jq sqlite3 curl vim neovim lsof iproute2 less nginx \
		make tree net-tools file build-essential \
		psmisc bsdmainutils sudo socat \
		openssh-server openssh-client \
		libcap2-bin unzip util-linux rsync \
		iputils-ping netcat-openbsd \
		systemd systemd-sysv dbus-user-session \
		atop btop iotop ncdu \
		bubblewrap && \
	locale-gen en_US.UTF-8 && \
	update-locale LANG=en_US.UTF-8 && \
	# openssh-server generates host keys during package configuration.
	# Do not bake those per-image private keys into exeuntu.
	rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub && \
	# Allow non-root users to use ping without sudo by granting CAP_NET_RAW.
	setcap cap_net_raw=+ep /usr/bin/ping && \
	# Remove policy-rc.d so services can start normally under systemd at runtime.
	rm -f /usr/sbin/policy-rc.d && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Tailscale (keyring method, per https://tailscale.com/install.sh)
# This must run after ca-certificates and curl are installed.
RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tailscale && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=exeuntu-cli /out/exeuntu /usr/local/bin/exeuntu
COPY exeuntu-install /usr/local/bin/exeuntu-install
RUN chmod 0755 /usr/local/bin/exeuntu-install

# Configure systemd
RUN rm -f /etc/systemd/system/multi-user.target.wants/console-setup.service \
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
	(systemctl disable docker.service containerd.service getty.target systemd-logind.service tailscaled.service \
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
		   multipathd.service || true) && \
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

RUN mkdir -p /home/exedev /home/exedev/.codex && \
    chown exedev:exedev /home/exedev /home/exedev/.codex

USER exedev

WORKDIR /home/exedev

# Update PATH in .bashrc to include .local/bin and set XDG_RUNTIME_DIR for systemd user services
# XDG paths are not autopopulated despite the presense of libpam-systemd. Manually add them here.
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.profile

# Install Bun, the latest stable Herdr, and the latest stable Collie release.
# Make passes their published versions as a cache key so newly published
# releases invalidate these layers.
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

# Configure git to use 'main' as default branch name
RUN git config --global init.defaultBranch main

# Switch back to root to install systemd service
USER root
RUN ln -sf /home/exedev/.local/bin/bun /usr/local/bin/bun && \
    ln -sf /home/exedev/.local/bin/herdr /usr/local/bin/herdr

# Disable Ubuntu's default MOTD (the sudo hint, etc.)
RUN rm -rf /etc/update-motd.d/* /etc/motd && touch /home/exedev/.hushlogin && chown exedev:exedev /home/exedev/.hushlogin

# Add custom MOTD to exedev's .bashrc (ignores .hushlogin - we handle that ourselves)
COPY motd-snippet.bash /tmp/motd-snippet.bash
RUN cat /tmp/motd-snippet.bash >> /home/exedev/.bashrc && rm /tmp/motd-snippet.bash

# Create systemd oneshot service for /exe.dev/setup script
COPY exe-setup.service /etc/systemd/system/exe-setup.service
RUN chmod 644 /etc/systemd/system/exe-setup.service && \
    systemctl enable exe-setup.service

# TODO(crawshaw/philip): This is called init so that exetini decides
# this wrapper script is an init, and exec's it rather than forking it.
# It would be better if you could indicate that via an env variable or something.
COPY init-wrapper.sh /usr/local/bin/init

# Configure Codex and install the shared agent instructions.
RUN mkdir -p /home/exedev/.codex && \
    chown -R exedev:exedev /home/exedev/.codex
COPY AGENTS.md /home/exedev/.codex/AGENTS.md
RUN chown exedev:exedev /home/exedev/.codex/AGENTS.md

# Install Codex through exeuntu's direct updater.
USER root
RUN exeuntu update codex && \
    test -x /usr/local/bin/codex && \
    /usr/local/bin/codex --version

# Custom nginx config and index page (nginx is installed but disabled by default)
COPY nginx.conf /etc/nginx/sites-available/default
COPY index.html /var/www/html/index.html
RUN chmod 644 /var/www/html/index.html

# Install xterm-ghostty terminfo for Ghostty terminal support
COPY xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN tic -x - < /tmp/xterm-ghostty.terminfo && rm /tmp/xterm-ghostty.terminfo

# Install the architecture-matched static Herdr API release. Make and the image
# publishing workflow resolve the latest release and pass its version here;
# direct Docker builds default to the version below.
ARG TARGETARCH
ARG HERDR_API_REPOSITORY=aaronS7/herdr-api
ARG HERDR_API_VERSION=0.1.0
RUN [[ "${HERDR_API_REPOSITORY}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && \
    [[ "${HERDR_API_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] && \
    case "${TARGETARCH}" in \
        amd64) expected_arch='x86-64' ;; \
        arm64) expected_arch='ARM aarch64' ;; \
        *) echo "Herdr API has no release binary for architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    archive="herdr-api-v${HERDR_API_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    release_url="https://github.com/${HERDR_API_REPOSITORY}/releases/download/v${HERDR_API_VERSION}" && \
    mkdir -p /tmp/herdr-api-release /usr/local/share/herdr-api && \
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 120 \
        "${release_url}/${archive}" -o "/tmp/herdr-api-release/${archive}" && \
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 30 \
        "${release_url}/${archive}.sha256" -o "/tmp/herdr-api-release/${archive}.sha256" && \
    (cd /tmp/herdr-api-release && sha256sum --check "${archive}.sha256") && \
    tar -xzf "/tmp/herdr-api-release/${archive}" -C /usr/local/bin herdr-api && \
    chmod 0755 /usr/local/bin/herdr-api && \
    file /usr/local/bin/herdr-api | grep -F "${expected_arch}" && \
    file /usr/local/bin/herdr-api | grep -Eq 'statically linked|static-pie linked' && \
    printf 'v%s\n' "${HERDR_API_VERSION}" > /usr/local/share/herdr-api/revision && \
    rm -r /tmp/herdr-api-release

# Start Herdr API with the user's systemd manager. Its separate config unit
# generates a per-VM bearer token at first boot.
COPY herdr-api-init /usr/local/libexec/herdr-api-init
COPY herdr-api-config.service /etc/systemd/user/herdr-api-config.service
COPY herdr-api.service /etc/systemd/user/herdr-api.service
RUN chmod 0755 /usr/local/libexec/herdr-api-init && \
    chmod 0644 /etc/systemd/user/herdr-api-config.service \
        /etc/systemd/user/herdr-api.service && \
    systemctl --global enable herdr-api.service

# Expose the default web server port. Herdr API and Collie remain loopback-only.
EXPOSE 8000

LABEL "exe.dev/login-user"="exedev"
CMD ["/usr/local/bin/init"]
