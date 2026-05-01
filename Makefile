.PHONY: help dev test lint scan ci build run

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

dev: ## Start local Rails server
	cd app && bin/rails server

test: ## Run tests
	cd app && bin/rails test test:system

lint: ## Run RuboCop
	cd app && bin/rubocop -f progress

scan: ## Run security scans (Brakeman + importmap audit)
	cd app && bin/brakeman --no-pager --quiet
	cd app && bin/importmap audit

ci: scan lint test ## Run all CI checks locally

plan: ## Run terraform plan (requires ALERT_EMAIL env var or prompts)
	cd infrastructure && terraform plan -var="alert_email=$${ALERT_EMAIL:-adr@maas.ca}"

url: ## Print the deployed app URL
	@INSTANCE_ID=$$(AWS_PROFILE=admin aws ssm get-parameter --name /thrive-exercise/deploy/INSTANCE_ID --query Parameter.Value --output text --region us-west-2) && \
	DNS=$$(AWS_PROFILE=admin aws ec2 describe-instances --instance-ids $$INSTANCE_ID --query 'Reservations[0].Instances[0].PublicDnsName' --output text --region us-west-2) && \
	echo "http://$$DNS"

build: ## Build Docker image locally
	docker build -t thrive-exercise:local -f app/Dockerfile app

run: ## Run Docker image locally (no AWS required)
	docker run --rm \
		-e SECRET_KEY_BASE=$$(openssl rand -hex 64) \
		-e USERNAME=dev \
		-e PASSWORD=dev \
		-p 3000:80 \
		thrive-exercise:local
