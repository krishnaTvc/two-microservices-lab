#!/usr/bin/env bash
# Runs on EC2 A after tests pass and the workflow has assumed its OIDC role.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'Expected: SERVICE JAR_PATH' >&2; exit 1; }
service=$1
jar=$2
case "$service" in users-service|orders-service) ;; *) echo 'Invalid service.' >&2; exit 1 ;; esac
: "${AWS_REGION:?Set the repository Actions variable AWS_REGION}"
: "${ARTIFACT_BUCKET:?Set the repository Actions variable ARTIFACT_BUCKET}"
: "${APP_INSTANCE_ID:?Set the repository Actions variable APP_INSTANCE_ID}"
: "${GITHUB_SHA:?Run this script from GitHub Actions}"
: "${GITHUB_RUN_ID:?Missing GitHub run ID}"
: "${GITHUB_RUN_ATTEMPT:?Missing GitHub run attempt}"
[[ $GITHUB_SHA =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid commit SHA.' >&2; exit 1; }
[[ $GITHUB_RUN_ID =~ ^[0-9]+$ && $GITHUB_RUN_ATTEMPT =~ ^[0-9]+$ ]] || exit 1
[[ $ARTIFACT_BUCKET =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo 'Invalid bucket name.' >&2; exit 1; }
[[ $APP_INSTANCE_ID =~ ^i-[a-f0-9]+$ ]] || { echo 'Invalid EC2 instance ID.' >&2; exit 1; }
[[ -f $jar ]] || { echo "JAR not found: $jar" >&2; exit 1; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd "$script_dir/.." && pwd)
release="${GITHUB_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
prefix="s3://$ARTIFACT_BUCKET/$service/$release"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
digest=$(sha256sum "$jar" | cut -d ' ' -f 1)
printf '%s  app.jar\n' "$digest" > "$work/app.jar.sha256"
aws s3 cp "$jar" "$prefix/app.jar" --region "$AWS_REGION" --only-show-errors
aws s3 cp "$work/app.jar.sha256" "$prefix/app.jar.sha256" --region "$AWS_REGION" --only-show-errors
aws s3 cp "$project_dir/deploy/deploy-service.sh" "$prefix/deploy-service.sh" \
  --region "$AWS_REGION" --only-show-errors

# JSON and shell quoting are generated separately, so inputs cannot become shell code.
export LAB_SERVICE="$service" LAB_RELEASE="$release"
python3 - "$work/parameters.json" <<'PY'
import json, os, shlex, sys
e = os.environ
q = shlex.quote
uri = f"s3://{e['ARTIFACT_BUCKET']}/{e['LAB_SERVICE']}/{e['LAB_RELEASE']}/deploy-service.sh"
arguments = ' '.join(q(e[key]) for key in ('LAB_SERVICE', 'ARTIFACT_BUCKET', 'LAB_RELEASE', 'AWS_REGION'))
command = '\n'.join([
    'set -eu',
    'deploy_script=$(mktemp /var/tmp/hello-deploy.XXXXXX)',
    'trap \'rm -f "$deploy_script"\' EXIT',
    f'aws s3 cp {q(uri)} "$deploy_script" --region {q(e["AWS_REGION"])} --only-show-errors',
    f'bash "$deploy_script" {arguments}',
])
with open(sys.argv[1], 'w') as file:
    json.dump({'commands': [command], 'executionTimeout': ['600']}, file)
PY
command_id=$(aws ssm send-command --region "$AWS_REGION" \
  --instance-ids "$APP_INSTANCE_ID" --document-name AWS-RunShellScript \
  --comment "Deploy $service $release" --timeout-seconds 120 \
  --parameters "file://$work/parameters.json" --query Command.CommandId --output text)
echo "SSM command: $command_id"

# SSM is asynchronous. A submitted command is not a successful deployment.
for ((attempt=1; attempt<=156; attempt++)); do
  if status=$(aws ssm get-command-invocation --region "$AWS_REGION" \
      --command-id "$command_id" --instance-id "$APP_INSTANCE_ID" \
      --query Status --output text 2>"$work/ssm-error"); then
    case "$status" in
      Success)
        aws ssm get-command-invocation --region "$AWS_REGION" \
          --command-id "$command_id" --instance-id "$APP_INSTANCE_ID" \
          --query StandardOutputContent --output text
        if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
          printf '### %s deployed\n\n- Release: `%s`\n- SSM command: `%s`\n- Health check: passed\n' \
            "$service" "$release" "$command_id" >> "$GITHUB_STEP_SUMMARY"
        fi
        exit 0 ;;
      Failed|Cancelled|TimedOut|Cancelling)
        aws ssm get-command-invocation --region "$AWS_REGION" \
          --command-id "$command_id" --instance-id "$APP_INSTANCE_ID" --output json
        exit 1 ;;
      Pending|InProgress|Delayed) ;;
      *) echo "Unexpected SSM status: $status" >&2; exit 1 ;;
    esac
  elif ! grep -q InvocationDoesNotExist "$work/ssm-error"; then
    cat "$work/ssm-error" >&2
    exit 1
  fi
  sleep 5
done
echo "Timed out waiting for SSM command $command_id. Inspect it before redeploying." >&2
exit 1
