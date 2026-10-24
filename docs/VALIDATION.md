# Validation — 24 October 2026

Checks completed before packaging:

| Check | Result |
| --- | --- |
| Independent users Maven build on Java 17 | Passed |
| Independent orders Maven build on Java 17 | Passed |
| Users HTTP integration tests: UI, JSON endpoint, health | 3 passed |
| Orders HTTP integration tests: UI, JSON endpoint, health | 3 passed |
| Both executable JARs started locally | Passed |
| Both browser UIs and their API buttons | Passed |
| Desktop and 360 px mobile layout checks | Passed |
| Browser JavaScript errors | None observed |
| All Bash scripts: syntax checks | Passed |
| Both workflows: YAML structure, variable names, service paths | Passed |
| IAM policy generation and JSON parsing | Passed |
| Deployment using mocked AWS/systemd: service isolation | Passed |
| Deployment using mocked AWS/systemd: failed health rollback | Passed |
| Deployment using mocked AWS/systemd: checksum rejection | Passed |
| Deployment using mocked AWS/systemd: failed first release cleanup | Passed |
| Publisher using mocked AWS: exact JAR upload and selected-service SSM request | Passed |
| systemd unit syntax validation | Passed |

AWS resources and GitHub repository access were not provided for a live deployment.
OIDC role assumption, S3 permissions, SSM connectivity, and actual systemd service
startup on your EC2 instance must be verified after you complete SETUP.md.
The local deployment checks used stand-ins for AWS APIs and systemd, not live AWS.

The ZIP contains source and configuration, without compiled `target/` directories,
local browser screenshots, test tooling, private keys, or AWS credentials.
