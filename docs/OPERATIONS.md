# Operations on EC2 B

## Service status and logs

```bash
sudo systemctl status users.service --no-pager
sudo systemctl status orders.service --no-pager
sudo journalctl -u users.service -n 100 --no-pager
sudo journalctl -u orders.service -n 100 --no-pager
```

Follow one service's logs:

```bash
sudo journalctl -u users.service -f
```

Check each application locally on the application server:

```bash
curl -fsS http://127.0.0.1:8081/health
curl -fsS http://127.0.0.1:8082/health
curl -fsS http://127.0.0.1:8081/api/hello
curl -fsS http://127.0.0.1:8082/api/hello
```

Both health endpoints return `UP`. Deployments check localhost health. Browser
access also requires the correct network route and application security group.

## Restart exactly one application

```bash
sudo systemctl restart users.service
```

Or:

```bash
sudo systemctl restart orders.service
```

These are independent processes. A restart of one does not restart the other.
They are enabled to start after a reboot once their `current.jar` links exist.
Applications run as distinct non-login service users; SSM performs installation
and restart commands as root.

## Release locations

| Service | Current JAR link | Retained releases |
| --- | --- | --- |
| Users | `/opt/hello-services/users-service/current.jar` | `/opt/hello-services/users-service/releases/` |
| Orders | `/opt/hello-services/orders-service/current.jar` | `/opt/hello-services/orders-service/releases/` |

The pipeline creates a unique release directory for each commit/run/attempt.
It verifies the downloaded JAR's SHA-256 checksum and atomically switches the
selected service's symlink before restarting it. A per-service file lock prevents
overlapping deployments. If startup/health fails, it restores the previous JAR
when one exists; the pipeline still fails so the bad release is visible.
On a failed first deployment, it stops that service because no prior JAR exists.

## Manually restore a retained release

First ensure no deployment is running for that service. Run on **EC2 B**:

```bash
sudo readlink -f /opt/hello-services/users-service/current.jar
sudo ls -1 /opt/hello-services/users-service/releases/
```

Choose the release identifier that should run, then replace `RELEASE_ID` below:

```bash
sudo bash -s -- RELEASE_ID <<'SH'
set -euo pipefail
base=/opt/hello-services/users-service
release=$1
[[ $release =~ ^[a-f0-9]{40}-[0-9]+-[0-9]+$ ]]
exec 9>/run/lock/hello-users-service.lock
flock -w 180 9
test -f "$base/releases/$release/app.jar"
ln -sfn "$base/releases/$release/app.jar" "$base/current.jar.next"
mv -Tf "$base/current.jar.next" "$base/current.jar"
systemctl restart users.service
SH
```

Wait for startup and verify:

```bash
curl -fsS http://127.0.0.1:8081/health
```

For orders, substitute `orders-service`, `orders.service`, and port `8082`.
This manual operation switches to an existing local JAR; it does not rebuild code.

## Retention and shutdown

Releases are retained to make rollback easy. Watch disk usage with `df -h` and
`sudo du -sh /opt/hello-services/*/releases`. Remove only old release directories
you have reviewed, keeping each current release and at least one known-good prior
release. Configure S3 lifecycle retention separately when you have chosen a policy.

When pausing the lab, stop both EC2 instances. A stopped runner cannot execute
jobs, and a stopped application VM cannot receive SSM deployment commands.
Public IPs may change when instances restart; instance IDs and the workflow
variables remain the same. EBS volumes, stored artifacts, and other retained
AWS resources can continue to incur charges while EC2 instances are stopped.
