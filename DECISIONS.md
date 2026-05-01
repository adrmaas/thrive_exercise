# Decision Log

## What I Found

The original repo had a working deployment but several significant problems:

- **Credentials on the instance** — the deploy workflow SSHed into EC2 and ran `aws configure` to write `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` directly to the instance's `~/.aws/config` on every deploy. An IAM instance role already existed but wasn't being used.
- **Destructive deploy** — `docker stop $(docker ps -a -q)` and `docker rm $(docker ps -a -q)` killed all containers before starting the new one, causing downtime on every deploy.
- **`production_secrets.json` committed** — plaintext credentials (`USERNAME`, `PASSWORD`) checked into the repo. The file was never loaded by the application.
- **`latest`-only image tag** — no git SHA tagging, making rollback impossible.
- **No VPC** — infrastructure relied on the default VPC with a security group passed as an external variable, making the IaC incomplete and non-portable.
- **No observability** — no logs, metrics, alarms, or dashboards.
- **Instance type** — `t2.medium` is not free-tier eligible.
- **Kamal present but unused** — `config/deploy.yml` had placeholder values and the deploy workflow bypassed it entirely in favour of raw SSH commands.

---

## What I Fixed and Why

- **Replaced SSH deploy with Kamal** — zero-downtime rolling deploys, health checks before cutover, rollback capability. Kamal was already in the repo and purpose-built for this.
- **Removed credential injection** — IAM instance role now handles ECR pull. Secrets (`SECRET_KEY_BASE`, `USERNAME`, `PASSWORD`, `SSH_PRIVATE_KEY`) stored in SSM Parameter Store, fetched at deploy time. No credentials on the instance.
- **Deleted `production_secrets.json`** — plaintext credentials in the repo with no purpose.
- **Git SHA image tagging** — every deploy pushes both a SHA tag and `latest`, enabling rollback to any previous commit.
- **Full IaC** — VPC with public/private subnets across 2 AZs, security group, EC2, ECR, IAM policies, SSM parameters, CloudWatch, SNS all defined in Terraform. Security group no longer passed as an external variable.
- **Switched to Amazon Linux 2023 ECS-optimized AMI** — Docker pre-installed, SSM Agent pre-installed, no `user_data` bootstrap needed.
- **Closed port 22** — all access via SSM Session Manager tunnel. SSH key stored in SSM, not on disk.
- **Observability** — CloudWatch Agent ships Docker logs and memory/disk metrics. CPU, status check, and HTTP health check alarms routed to SNS email. CloudWatch dashboard for at-a-glance visibility.
- **Downsized to `t2.micro`** — free-tier eligible.
- **Split CI/CD into three workflows** — `ci` (tests/lint/scan), `deploy` (app changes), `infrastructure` (Terraform). Separate IAM credentials with scoped permissions for each.

---

## What I Left Alone and Why

- **RDS** — the app is a stateless landing page with no models, no database queries, and no schema. There is nothing to share between instances. Adding RDS would be premature. See ADR-002.
- **ALB / ECS Fargate** — correct production architecture but not free-tier eligible. Documented as the intended future path. See ADR-001.
- **Cloudflare DNS** — would enable round-robin across multiple instances without an ALB. Left out of scope for this exercise but documented as the zero-cost path to multi-instance.
- **Structured logging (lograge)** — CloudWatch Logs is receiving logs. Adding lograge would improve queryability but is a low-priority improvement given the app's simplicity.
- **AWS X-Ray** — no downstream dependencies to trace. See ADR-006.
- **NAT Gateway** — no resources in private subnets. See ADR-003.

---

## What I'd Do Next

The first thing I'd tackle is getting a domain and putting Cloudflare in front of the service. This unlocks HTTPS via Kamal's built-in Let's Encrypt, enables round-robin DNS across a second instance, and adds DDoS protection and edge caching — all at zero cost. It's the single change that most improves the production-readiness of the current architecture without requiring a budget increase.

After that, in order:
1. **Second EC2 instance + Cloudflare round-robin** — basic redundancy without an ALB
2. **ALB + ECS Fargate** — when budget allows, replace the EC2/Kamal setup with a proper managed container platform with auto scaling
3. **RDS PostgreSQL** — when the application grows to have real models or shared state
4. **Optimise Docker build** — the build step is the biggest bottleneck in the deploy pipeline; a remote builder or better layer caching would significantly improve iteration speed
5. **Grafana Cloud** — free tier, connects to CloudWatch, better dashboards than native CloudWatch

---



**Date:** 2026-04-30
**Status:** Accepted

### Decision
Use Kamal with an EC2 instance instead of ECS Fargate, an Application Load Balancer, or other managed container services.

The repo already contains Kamal configuration. Kamal provides zero-downtime rolling deploys proxy. Round-robin DNS via Cloudflare (free tier) could distribute traffic across instances without requiring an ALB.  While Cloudflare should work it will remain out of scope for this exercise.

The chosen stack:
- Kamal for zero-downtime container deploys
- An EC2 instances (`t2.micro`, free tier) to stick below the free tier budget
- SSM Parameter Store for secrets management

Sticking to the free tier, later one could add:
- Cloudflare free tier for round-robin DNS, SSL termination, DDoS protection, and basic WAF
- Grafana clould for visibility

### Rationale
ECS Fargate, ALB, NLB, and RDS are not free-tier eligible. The exercise constraint is to avoid incurring AWS costs. Two `t2.micro` EC2 instances are free-tier eligible (750 hours/month combined). Kamal is already present in the repo and is purpose-built for this deployment pattern.

### Consequences
- No managed load balancer — traffic distribution relies on DNS round-robin, which has no health-check-based failover on Cloudflare's free plan.
- When budget allows, the correct production path is ALB + ECS Fargate with auto scaling. This is documented as the intended future architecture.
- Route 53 is not strictly free ($0.50/hosted zone/month) — Cloudflare free tier is the zero-cost alternative.

---

## ADR-002: Defer RDS — app is stateless

**Date:** 2026-04-30
**Status:** Accepted

### Decision
Do not provision RDS. The app runs without a database.

### Rationale
The application is a stateless landing page. It reads two environment variables (`USERNAME`, `PASSWORD`) and renders them. No models, sessions, background jobs, or caching are in use. There is no `schema.rb` and no application tables exist. Running multiple instances requires no shared state.

### Consequences
- When the application grows to include models, jobs, caching, or sessions, provision RDS PostgreSQL (Multi-AZ) and update `database.yml` to use `adapter: postgresql` with `DATABASE_URL` injected at runtime.
- The `sqlite3` gem and Solid Queue/Cache/Cable schema files remain in place but are not exercised in production.

---

## ADR-003: Custom VPC without NAT Gateway

**Date:** 2026-04-30
**Status:** Accepted

### Decision
Provision a dedicated VPC with public and private subnets across 2 AZs. Deploy EC2 instances into public subnets. Do not provision a NAT Gateway.

### Rationale
The default VPC offers no isolation, no subnet segmentation, and no room to grow. A dedicated VPC with public/private subnet tiers is the correct baseline.

NAT Gateway costs ~$0.045/hour (~$32/month) and is not free-tier eligible. There are currently no resources in private subnets, so a NAT Gateway provides no benefit.

### Consequences
- Private subnets are provisioned and ready for future use (RDS, ECS, etc.).
- When private subnet resources need outbound internet access, add a NAT Gateway (one per AZ for HA) or a NAT instance (EC2-based, free-tier eligible, higher ops overhead).

---

## ADR-004: Replace credentials.yml.enc with environment-injected SECRET_KEY_BASE

**Date:** 2026-04-30
**Status:** Accepted

### Decision
Delete `credentials.yml.enc` and `master.key`. Generate a random `SECRET_KEY_BASE` via Terraform and store it in SSM Parameter Store. Inject it into the container at deploy time via Kamal.

### Rationale
Nothing in the app reads from `credentials.yml.enc` — the only references to `credentials.dig(...)` are commented-out SMTP config. The file exists only because Rails generates it by default.

Keeping it creates an operational burden: `RAILS_MASTER_KEY` must be manually sourced, stored, and kept in sync with the encrypted file. If the key is lost, the file is unrecoverable.

Rails 8 supports `SECRET_KEY_BASE` injected directly via environment variable with no credentials file required.

### Consequences
- `SECRET_KEY_BASE` is generated once on first `terraform apply` and stored in SSM as a SecureString. The value is also in Terraform state, which is encrypted at rest in S3.
- Running the production container locally requires passing any random `SECRET_KEY_BASE` — no SSM access needed.
- If Rails credentials are needed in future (e.g. SMTP), re-introduce `credentials.yml.enc` with a new master key stored in SSM.

---

## ADR-005: Amazon Linux 2023 ECS-optimized AMI instead of Ubuntu

**Date:** 2026-05-01
**Status:** Accepted

### Decision
Use the Amazon Linux 2023 ECS-optimized AMI instead of Ubuntu 22.04 LTS.

### Rationale
The ECS-optimized AMI comes with Docker pre-installed and running, eliminating the need for a `user_data` bootstrap script to install Docker on first boot. This reduces boot time and removes a potential failure point.

Amazon Linux 2023 also ships with the AWS Systems Manager (SSM) Agent pre-installed and enabled by default. Combined with the `AmazonSSMManagedInstanceCore` IAM policy, this enables:
- Shell access via SSM Session Manager without SSH keys or open port 22
- Remote command execution via SSM Run Command
- CloudWatch Agent installation and configuration via SSM State Manager associations

The ECS agent included in the AMI is irrelevant to this deployment (we're using Kamal, not ECS) but is harmless and adds no cost.

Ubuntu would require `user_data` to install Docker and the SSM agent, adding complexity and boot time. Amazon Linux 2023 is purpose-built for AWS workloads and maintained by AWS with automatic security patching via SSM Patch Manager.

### Consequences
- Docker is available immediately on instance launch — no bootstrap delay.
- Port 22 can be closed entirely — all access via SSM Session Manager tunnel.
- SSH key pair is generated by Terraform, stored in SSM, and used by Kamal via the SSM tunnel for authentication. No key is stored on disk or in CI secrets.
- CloudWatch Agent installed and configured via SSM associations — no manual steps.
- The AMI is Amazon Linux-specific — package management uses `dnf` instead of `apt`, and some Ubuntu-specific tooling may not be available. This is acceptable for a containerized workload where the host OS is largely abstracted away.

---

## ADR-006: Observability stack — CloudWatch native, X-Ray deferred

**Date:** 2026-05-01
**Status:** Accepted

### Decision
Use AWS CloudWatch as the sole observability platform. Implement metrics, logs, alarms, and a dashboard. Defer AWS X-Ray tracing because of the lack of complexity in the application.

### Rationale
CloudWatch covers all four observability pillars within the AWS free tier:
- **Metrics** — EC2 standard metrics (CPU, network, status check) plus memory and disk via CloudWatch Agent
- **Logs** — Docker container logs shipped to `/app/thrive-exercise` log group via CloudWatch Agent, 7-day retention
- **Alarms** — CPU >80%, EC2 status check failure, and HTTP health check on `/up` via Route 53; all routed to SNS → email
- **Dashboard** — single pane showing CPU, memory, disk, status check, and alarm states

The CloudWatch Agent is installed and configured via SSM State Manager associations, requiring no manual instance access and no changes to the application or Dockerfile.

### On AWS X-Ray
X-Ray would provide distributed tracing — request-level visibility into latency, errors, and downstream calls. This would be valuable as the application grows to include database queries, external API calls, and background jobs. The Rails OpenTelemetry SDK (`opentelemetry-sdk` + `opentelemetry-exporter-otlp`) or the AWS X-Ray SDK for Ruby would be the implementation path.

X-Ray is deferred because the current application is a single-endpoint landing page with no downstream dependencies. There is nothing to trace. When the application gains meaningful business logic, X-Ray or an OTEL-compatible backend should be the first observability addition.

### Consequences
- No application-level request tracing or latency breakdown currently available.
- CloudWatch Logs Insights can be used for basic log-based analysis in the interim.
- Adding X-Ray requires: gem installation, Rails middleware configuration, and IAM policy (`xray:PutTraceSegments`, `xray:PutTelemetryRecords`) on the EC2 instance role.
