#!/usr/bin/env bash
# Runs as root on EC2 B through Systems Manager Run Command.
# Usage: bash deploy-service.sh SERVICE BUCKET RELEASE REGION
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Deployment must run as root through SSM.' >&2; exit 1; }
[[ $# -eq 4 ]] || { echo 'Expected: SERVICE BUCKET RELEASE REGION' >&2; exit 1; }
service=$1
bucket=$2
release=$3
region=$4
case "$service" in
  users-service) unit=users.service; port=8081 ;;
  orders-service) unit=orders.service; port=8082 ;;
  *) echo 'Invalid service.' >&2; exit 1 ;;
esac
[[ $bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo 'Invalid bucket name.' >&2; exit 1; }
[[ $release =~ ^[a-f0-9]{40}-[0-9]+-[0-9]+$ ]] || { echo 'Invalid release identifier.' >&2; exit 1; }
[[ $region =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || { echo 'Invalid AWS region.' >&2; exit 1; }

base="/opt/hello-services/$service"
[[ -d $base/releases ]] || { echo 'Run bootstrap-app-server.sh on this server first.' >&2; exit 1; }
exec 9>"/run/lock/hello-${service}.lock"
flock -w 180 9 || { echo 'Another deployment is still running.' >&2; exit 1; }

work=$(mktemp -d "$base/releases/.incoming.XXXXXX")
trap 'rm -rf "$work"' EXIT
prefix="s3://$bucket/$service/$release"
aws s3 cp "$prefix/app.jar" "$work/app.jar" --region "$region" --only-show-errors
aws s3 cp "$prefix/app.jar.sha256" "$work/app.jar.sha256" --region "$region" --only-show-errors
(cd "$work" && sha256sum --check app.jar.sha256)
chmod 755 "$work"
chmod 644 "$work/app.jar" "$work/app.jar.sha256"
release_dir="$base/releases/$release"
if [[ -d $release_dir ]]; then
  # An SSM retry may refer to an already-staged release. Never replace it in place.
  cmp "$work/app.jar" "$release_dir/app.jar" || { echo 'Release content differs.' >&2; exit 1; }
else
  mv "$work" "$release_dir"
fi

previous=''
if [[ -L $base/current.jar && -f $base/current.jar ]]; then
  previous=$(readlink -f "$base/current.jar")
fi
rollback() {
  result=$?
  trap - ERR
  set +e
  echo "Deployment failed for $service; restoring the previous release." >&2
  journalctl -u "$unit" -n 50 --no-pager >&2
  if [[ -n $previous ]]; then
    ln -sfn "$previous" "$base/current.jar.next"
    mv -Tf "$base/current.jar.next" "$base/current.jar"
    systemctl restart "$unit"
    echo 'Previous release restored. Check its health and journal.' >&2
  else
    systemctl stop "$unit"
    rm -f "$base/current.jar"
    echo 'First deployment failed; no previous release exists.' >&2
  fi
  exit "$result"
}
trap rollback ERR
ln -sfn "$release_dir/app.jar" "$base/current.jar.next"
mv -Tf "$base/current.jar.next" "$base/current.jar"
systemctl restart "$unit"
for ((attempt=1; attempt<=60; attempt++)); do
  if systemctl is-active --quiet "$unit" && \
      curl --fail --silent --connect-timeout 2 --max-time 3 "http://127.0.0.1:$port/health" | grep -qx UP; then
    trap - ERR
    echo "SUCCESS: $service release $release is healthy on port $port."
    exit 0
  fi
  sleep 2
done
echo 'Health check timed out.' >&2
false  # Trigger rollback and return a failed SSM command.
