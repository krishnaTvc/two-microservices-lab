#!/usr/bin/env bash
# Ubuntu EC2 helper. Run as root, or through sudo.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
if command -v aws >/dev/null 2>&1 && aws --version 2>&1 | grep -q 'aws-cli/2'; then
  aws --version
  exit 0
fi
case "$(uname -m)" in
  x86_64) architecture=x86_64 ;;
  aarch64) architecture=aarch64 ;;
  *) echo 'Unsupported CPU architecture.' >&2; exit 1 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --show-error --silent --location --retry 3 \
  "https://awscli.amazonaws.com/awscli-exe-linux-${architecture}.zip" -o "$work/awscliv2.zip"
unzip -q "$work/awscliv2.zip" -d "$work"
if [[ -d /usr/local/aws-cli ]]; then
  "$work/aws/install" --update
else
  "$work/aws/install"
fi
aws --version
