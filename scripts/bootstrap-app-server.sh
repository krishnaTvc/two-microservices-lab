#!/usr/bin/env bash
# Run once on EC2 B (Ubuntu 24.04).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd "$script_dir/.." && pwd)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jre-headless curl unzip python3 ca-certificates util-linux
bash "$script_dir/install-aws-cli.sh"
for short_name in users orders; do
  service="${short_name}-service"
  user="hello-${short_name}"
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "/opt/hello-services/$service" \
      --shell /usr/sbin/nologin "$user"
  fi
  install -d -m 755 "/opt/hello-services/$service/releases"
  install -m 644 "$project_dir/deploy/systemd/${short_name}.service" "/etc/systemd/system/${short_name}.service"
  systemctl enable "${short_name}.service"
done
systemctl daemon-reload

# The official Ubuntu AWS image commonly supplies SSM Agent as a snap.
# Fail with an actionable message rather than silently leaving deployment broken.
if systemctl list-unit-files amazon-ssm-agent.service --no-legend 2>/dev/null | grep -q '^amazon-ssm-agent.service'; then
  systemctl enable --now amazon-ssm-agent.service
elif command -v snap >/dev/null 2>&1 && snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap start amazon-ssm-agent
else
  echo 'SSM Agent was not found. Install/start it using docs/SETUP.md before deploying.' >&2
fi
echo 'Application server prepared. Services start after the first successful deployment.'
echo 'Attach the application EC2 instance role and confirm SSM reports this instance Online.'
