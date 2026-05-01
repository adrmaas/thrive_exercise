# Thrive Exercise

A Rails 8 web application deployed to AWS EC2 via Kamal, with infrastructure managed by Terraform.

---

## Developer Guide

### Prerequisites

- Ruby 3.3.6 (`rbenv` or `asdf` recommended)
- Docker Desktop
- Bundler (`gem install bundler`)

### Running locally

```console
cd app
bundle install
bin/rails server
```

Visit `http://localhost:3000`.

### Running the app in a container locally

No AWS credentials required.

```console
docker build -t thrive-exercise:local -f app/Dockerfile app

docker run \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e USERNAME=dev \
  -e PASSWORD=dev \
  -p 3000:80 \
  thrive-exercise:local
```

Visit `http://localhost:3000`.

### Running tests

```console
cd app
bin/rails test
bin/rails test:system
```

### Linting

```console
cd app
bin/rubocop
```

---

## Deploying with Kamal locally

Kamal can be run from your local machine as an alternative to triggering the GitHub Actions deploy workflow.

**Prerequisites:**
- AWS SSO authenticated (`aws sso login --profile admin`)
- `AWS_PROFILE=admin` exported
- SSH agent running with the deploy key loaded (see [Retrieving the SSH key](#retrieving-the-ssh-key))

**Deploy:**
```console
cd app
bundle exec kamal deploy
```

`config/deploy.yml` will automatically fetch the instance IPs and secrets from SSM using your local AWS credentials. No additional environment variables needed.

**To target a specific image tag:**
```console
IMAGE_TAG=<git-sha> bundle exec kamal deploy
```

**Other useful commands:**
```console
bundle exec kamal app logs -f       # tail logs across all instances
bundle exec kamal app exec --interactive --reuse "bin/rails console"
bundle exec kamal rollback <version>
```

---

## Infrastructure

### Prerequisites

- Terraform >= 1.9
- AWS CLI
- `gh` CLI (for setting GitHub Actions secrets)
- An AWS account — configure SSO:

```console
aws configure sso --profile admin
aws sso login --profile admin
export AWS_PROFILE=admin
```

### First-time setup

Create the Terraform state bucket (run once):

```console
infrastructure/bin/bootstrap
```

Or with explicit values:

```console
infrastructure/bin/bootstrap [region] [account_id] [aws_profile]
```

### Initialise and apply Terraform

```console
cd infrastructure
terraform init
terraform plan -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

### Setting GitHub Actions secrets

After `terraform apply`, push the generated secrets from SSM to GitHub Actions using the `gh` CLI (run from the repo root):

```console
for SECRET in SSH_PRIVATE_KEY SECRET_KEY_BASE USERNAME PASSWORD; do
  gh secret set "$SECRET" --body "$(aws ssm get-parameter \
    --name "/thrive-exercise/${SECRET}" \
    --with-decryption --query Parameter.Value --output text \
    --region us-west-2 --profile admin)"
done
```

### Accessing the instance

Access is via AWS SSM Session Manager — no SSH key or open port 22 required.

```console
# Get the instance ID from Terraform outputs
cd infrastructure && terraform output instance_id

# Start a session
aws ssm start-session --target <instance_id> --region us-west-2 --profile admin
```

Requires the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed locally.

### ECR — Container Registry

The ECR repository is provisioned by Terraform. Get the repository URL from Terraform outputs:

```console
cd infrastructure && terraform output ecr_repository_url
```

**Authenticate Docker to ECR:**

```console
aws ecr get-login-password --region us-west-2 --profile admin | \
  docker login --username AWS --password-stdin \
  071919116017.dkr.ecr.us-west-2.amazonaws.com
```

**Build and push to ECR:**

```console
ECR_URL=$(cd infrastructure && terraform output -raw ecr_repository_url)
IMAGE_TAG=$(git rev-parse --short HEAD)
docker build -t $ECR_URL:$IMAGE_TAG -t $ECR_URL:latest -f app/Dockerfile app
docker push $ECR_URL:$IMAGE_TAG
docker push $ECR_URL:latest
```
