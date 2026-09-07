#!/bin/bash
# Runs inside the image during builds, including both published architectures.
set -euo pipefail

service=/etc/systemd/system/shelley.service
socket=/etc/systemd/system/shelley.socket
config=/home/exedev/.config/shelley

test "$(readlink -f /etc/systemd/system/sockets.target.wants/shelley.socket)" = "$socket"
# Only the socket is enabled: exe.dev supplies the executable at VM creation.
test ! -e /etc/systemd/system/multi-user.target.wants/shelley.service
grep -Fxq 'ListenStream=127.0.0.1:9999' "$socket"
grep -Fxq 'Accept=no' "$socket"
grep -Fxq 'User=exedev' "$service"
grep -Fxq 'Group=exedev' "$service"
grep -Fxq 'ConditionPathExists=/usr/local/bin/shelley' "$service"
grep -Fq -- '-systemd-activation -require-header X-Exedev-Userid' "$service"
grep -Fq -- '-config /exe.dev/shelley.json' "$service"
grep -Fq -- "-db $config/shelley.db" "$service"
grep -Fq 'Environment=PATH=/headless-shell:' "$service"
test "$(stat -c %a "$service")" = 644
test "$(stat -c %a "$socket")" = 644

for path in /home/exedev/.config "$config" "$config/AGENTS.md"; do
    test "$(stat -c %U:%G "$path")" = exedev:exedev
done
cmp "$config/AGENTS.md" /home/exedev/.codex/AGENTS.md
runuser -u exedev -- test -w "$config"
test "$(command -v headless-shell)" = /headless-shell/headless-shell
runuser -u exedev -- headless-shell --version
command -v convert
command -v ffmpeg
fc-list | grep . >/dev/null
echo 'Shelley image checks passed'
