#!/usr/bin/env bash
# Run once on EC2 A (Ubuntu 24.04, x86_64).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jdk-headless maven git curl unzip python3 ca-certificates
bash "$script_dir/install-aws-cli.sh"
java -version
mvn --version
echo 'Next: register the GitHub runner as ubuntu; add the custom label aws-lab.'
echo 'Use the current Linux x64 commands shown in repository Settings > Actions > Runners.'
echo 'Then install and start the runner service using sudo ./svc.sh install ubuntu and sudo ./svc.sh start.'
