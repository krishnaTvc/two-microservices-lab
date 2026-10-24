# Setup: one repository, two pipelines, two EC2 machines

Follow the steps in order. Commands assume Ubuntu 24.04 and Bash. Use x86_64
instances because the workflows request the `x64` runner label. Run AWS resource
creation in your own account; no resources are created by extracting this ZIP.

## 1. Know which machine does what

| Component | Responsibility |
| --- | --- |
| EC2 A: `hello-runner` | Builds and tests both apps, assumes an AWS role through OIDC, publishes JARs, sends SSM deployment commands |
| EC2 B: `hello-app` | Downloads JARs using its own instance role; runs two separate Java processes through systemd |
| Private S3 bucket | Stores application releases and their deployment scripts |
| GitHub repository | Contains both services and two separate workflows |

For the lab, allow at least 2 GB RAM on each instance. Your existing t2.medium
can be used for either role. The runner needs a JDK and Maven; the application
server needs only the Java runtime. Keep enough disk space for Maven dependencies
and retained releases; 16–20 GB EBS per VM is a reasonable starting point.

For the simplest network setup, place both VMs in a public subnet with an internet
gateway route and public IPv4 addresses. Both require outbound internet/DNS access
for installation and AWS/GitHub access. S3 and SSM access can also be supplied by
VPC endpoints if you later move the application VM to a private subnet.

| Security group | Inbound rules for this lab |
| --- | --- |
| Runner | No inbound rule for GitHub Actions. If using SSH for administration, TCP 22 from your current public IP `/32` |
| Application | TCP 8081 and 8082 from your current public IP `/32`. Optional TCP 22 from that same IP for initial administration |

SSM deployment uses the instance's outbound connection; it does not need an
inbound deployment port. Use an EC2 key pair if you intend to use SSH. Keep the
key on your laptop, outside the repository. Use the Ubuntu login name `ubuntu`.

## 2. Create a private GitHub repository

Create an **empty private repository** named, for example, `two-microservices-lab`.
Use `main` as its default branch. You will push the extracted project after
configuration is ready. The ZIP includes `.github/`; do not omit that directory.

This persistent self-hosted runner is intended for your own code and trusted
collaborators in the private lab repository. PR jobs execute repository code on
the runner. Use isolated ephemeral runners or GitHub-hosted PR validation before
accepting untrusted contributions. Do not use `pull_request_target` to execute PR code.

## 3. Create a private S3 artifact bucket

In S3, create a uniquely named general-purpose bucket in the same AWS Region
as the VMs. Keep **Block all public access** enabled, ACLs disabled, and default
**SSE-S3** encryption. Enable versioning if desired.

Record these values:

| Value | Example placeholder |
| --- | --- |
| AWS account ID | `123456789012` |
| Region | `ap-south-1` |
| Bucket | `hello-artifacts-YOUR-UNIQUE-SUFFIX` |
| Application EC2 instance ID | `i-0123456789abcdef0` |
| GitHub owner | Your username or organization |
| Repository | `two-microservices-lab` |

The example account and instance IDs are placeholders. Use your real values.
If your organization requires a customer-managed KMS key, add the corresponding
KMS permissions to the two roles; the supplied policies assume SSE-S3.

## 4. Generate the IAM policy JSON files

On your laptop in WSL, or on an administration machine, run this from the
extracted project root after replacing the example values:

```bash
python3 scripts/render-iam.py \
  --account-id 123456789012 \
  --region ap-south-1 \
  --bucket hello-artifacts-YOUR-UNIQUE-SUFFIX \
  --app-instance-id i-0123456789abcdef0 \
  --owner YOUR_GITHUB_OWNER \
  --repo two-microservices-lab
```

This only writes three JSON files under `iam/rendered/`; it makes no AWS calls.
Git ignores that directory. Review the generated values before using them.

## 5. Configure the application VM's IAM role

In IAM, create a role named `hello-app-ec2-role` with trusted entity **AWS service → EC2**.
The equivalent trust document is `iam/app-ec2-trust.json`.

Attach:

1. AWS-managed policy `AmazonSSMManagedInstanceCore`.
2. An inline policy using `iam/rendered/app-s3-read.json`.

Attach this role to **EC2 B**, using EC2 → instance → Actions → Security → Modify IAM role.
This role lets the application server communicate with SSM and download artifacts.
The server does not receive the workflow's credentials and does not run `aws configure`.

The runner does not need an instance role with S3 upload or deployment permissions:
the workflow obtains those through OIDC. You may attach an SSM-only instance role
to the runner if you want SSM access for administration.

## 6. Configure GitHub OIDC and the workflow role

In IAM → Identity providers, create an OpenID Connect provider if it does not
already exist in this AWS account:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Create a role named `hello-github-deploy-role`. Use **Custom trust policy** and
paste `iam/rendered/oidc-trust.json`. Add an inline permissions policy using
`iam/rendered/workflow-permissions.json`.

Copy its ARN, for example:

```text
arn:aws:iam::123456789012:role/hello-github-deploy-role
```

The trust policy allows only the named repository on `main`. These workflows
do not configure a GitHub Environment, so their expected default OIDC subject is:

```text
repo:YOUR_GITHUB_OWNER/two-microservices-lab:ref:refs/heads/main
```

GitHub numeric user/repository IDs are not required by this default subject.
If you previously customized the repository/organization OIDC subject to contain
IDs, that customized subject must match the trust policy instead. If you add
`environment:` to these jobs, update the trust policy to match the environment
subject and restrict that environment to `main`. Keep this lab's default branch
subject until the basic deployment works.

**OIDC authenticates the workflow to AWS. Registering the runner with GitHub is
a separate step.** No permanent AWS access-key secrets are needed in GitHub.

The supplied deployment role can execute SSM shell commands as root on the one
specified application instance. Keep it scoped to this lab instance and trusted
repository. Both services share that role for this small lab.

## 7. Prepare EC2 B: application server

Copy this project to the application server. One option from your laptop/WSL is:

```bash
scp -i /path/to/your-key.pem -r two-microservices-lab ubuntu@APP_PUBLIC_IP:~/
ssh -i /path/to/your-key.pem ubuntu@APP_PUBLIC_IP
```

Run on **EC2 B**:

```bash
cd ~/two-microservices-lab
sudo bash scripts/bootstrap-app-server.sh
```

This installs the Java runtime and AWS CLI, creates two service users and release
directories, and installs/enables the two systemd units. It does not start the
applications until their first release is available.

Confirm the SSM Agent is running. Ubuntu AWS images usually include it as a snap:

```bash
sudo snap services amazon-ssm-agent
```

If it is absent, install it once:

```bash
sudo snap install amazon-ssm-agent --classic
sudo snap start amazon-ssm-agent
```

If it was installed as a Debian package, use:

```bash
sudo systemctl status amazon-ssm-agent
```

Use one installation method; do not install a second agent over an existing one.
Confirm Systems Manager lists EC2 B as a managed node with **Online** ping status.
Allow a few minutes after attaching the role. If it stays offline, check its
instance role, running agent, Region, outbound HTTPS/DNS, and internet/endpoint routing.

## 8. Prepare EC2 A: GitHub Actions runner

Copy the project onto **EC2 A** using the same SCP method, then run:

```bash
cd ~/two-microservices-lab
sudo bash scripts/bootstrap-runner.sh
```

In GitHub, open your repository → Settings → Actions → Runners → New self-hosted runner.
Choose **Linux / x64**. Follow the current download and configuration commands
shown by GitHub, running them as `ubuntu`, not root. Use a separate directory such
as `/home/ubuntu/actions-runner` for the runner installation.

During configuration:

- Runner name: `hello-ec2-runner`.
- Extra custom label: **`aws-lab`**.
- Keep the standard labels `self-hosted`, `linux`, and `x64`.
- Keep the default `_work` directory.

Install/start the runner as a background service from its installation directory:

```bash
cd ~/actions-runner
sudo ./svc.sh install ubuntu
sudo ./svc.sh start
sudo ./svc.sh status
```

GitHub should show the runner **Idle**. It stays available after your SSH session
closes. The runner's registration token comes from GitHub; do not store it in
this repository. The runner uses outbound HTTPS to reach GitHub.

## 9. Set the five GitHub Actions variables

Repository → Settings → Secrets and variables → Actions → **Variables** → New repository variable.

| Name | Value |
| --- | --- |
| `AWS_REGION` | Your Region, e.g. `ap-south-1` |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `AWS_ROLE_ARN` | ARN of `hello-github-deploy-role` |
| `ARTIFACT_BUCKET` | Bucket name only, without `s3://` |
| `APP_INSTANCE_ID` | EC2 B's instance ID, not the runner's ID |

These are configuration variables. The YAML reads them with `vars.*`; placing
them under Secrets without changing the YAML will not supply their values.
Do not set `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` for this project.

## 10. Push the project and deploy

On your laptop/WSL, enter the extracted project directory. Replace the owner/repository
in this example. Authenticate Git using your normal GitHub method:

```bash
git init -b main
git add .
git commit -m "Add two independently deployed Hello World services"
git remote add origin https://github.com/YOUR_GITHUB_OWNER/two-microservices-lab.git
git push -u origin main
```

Push the **contents** of the extracted project as the repository root. Do not put
the project inside another folder, or GitHub will not find `.github/workflows/`.

Both workflows trigger on the initial push because both service folders are new.
With one runner installation, one job runs and the other waits.

Each pipeline performs these steps:

1. Checks out the triggering commit.
2. Runs `mvn clean verify` for its own service, including HTTP tests.
3. Obtains temporary AWS credentials through GitHub OIDC.
4. Uploads the JAR, checksum, and deployment script to a unique S3 prefix.
5. Sends an SSM command to EC2 B.
6. Downloads and verifies the JAR there, switches that service's symlink, and restarts its unit.
7. Waits for SSM to finish successfully after the local HTTP health check passes.

Artifacts use this key pattern:

```text
SERVICE/COMMIT_SHA-RUN_ID-RUN_ATTEMPT/app.jar
```

The application server does not compile source or clone the repository during
deployment. It runs the JAR already built by the selected pipeline.

When both workflows finish successfully, open these in your browser:

```text
http://APP_PUBLIC_IP:8081/
http://APP_PUBLIC_IP:8082/
```

Use `http`, not `https`, for this lab. Click **Call this service** on each page.
If EC2 B has no public IP, reach it through your private network or use an
appropriate SSM/SSH port-forwarding setup instead.

## 11. Prove independent deployment

Create a feature branch:

```bash
git switch -c feature/users-greeting
```

Edit the visible greeting in `users-service/src/main/resources/static/index.html`.
Update its expected heading in `users-service/src/test/java/com/example/users/ApplicationTest.java`
if you change the `<h1>`, because the test checks that heading.

```bash
git add users-service
git commit -m "Update users greeting"
git push -u origin feature/users-greeting
```

Open a PR into `main`: only the users workflow tests/builds; it does not deploy.
Merge it: only the users workflow deploys. The orders process keeps running.
Refresh the users page to see your change. To keep tests unchanged, edit the
introductory paragraph instead of the heading.

For manual deployment, open Actions, choose **Users service CI/CD** or **Orders
service CI/CD**, choose Run workflow, and select `main`.

## 12. Useful troubleshooting checks

| Symptom | Check |
| --- | --- |
| Workflow waits for a runner | Runner is Idle/online; custom label is exactly `aws-lab`; Linux x64 matches the job |
| Workflow is missing | `.github/workflows/` is at the repository root; workflows are committed to `main` |
| UI edit did not trigger anything | Commit was pushed; it touches the right folder; event targets `main` or a PR into `main` |
| AWS variables missing | All five are repository Actions **Variables**, matching the exact names |
| OIDC role assumption fails | Exact owner/repo/main subject; no unexpected Environment/custom subject; provider audience is `sts.amazonaws.com` |
| S3 upload denied | Workflow role can `PutObject` under the selected service prefix; bucket policies do not deny it |
| S3 download denied on EC2 B | Application instance role has `GetObject`; bucket/Region match; no restrictive bucket or KMS policy |
| SSM target unavailable | EC2 B is Online in Systems Manager, in the workflow Region, with the right role and network access |
| Browser cannot connect | Both deployments passed; use app VM's current public IP, HTTP, correct port, and your current IP in its security group |
| Deployment fails health check | Read SSM output and `journalctl -u users.service` / `orders.service` on EC2 B |
| Changed a systemd unit file | Copy updated files to EC2 B and rerun `bootstrap-app-server.sh`; restart that service after reviewing the unit change |

Service-specific workflow path filters can leave skipped required checks pending.
Do not make both filtered workflows unconditional required checks for every PR.
For advanced branch protection, add an always-running change-aware gate later.

See [OPERATIONS.md](OPERATIONS.md) for logs, restarting one service, and rollback.
