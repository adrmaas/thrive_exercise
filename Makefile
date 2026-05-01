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

dashboard: ## Print the CloudWatch dashboard URL
	@echo "https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=thrive-exercise"

cloudwatch-agent: ## Re-run CloudWatch Agent configuration (run if mem/disk metrics are missing)
	@ASSOC_ID=$$(AWS_PROFILE=admin aws ssm list-associations --region us-west-2 \
		--query "Associations[?Name=='AmazonCloudWatch-ManageAgent'].AssociationId" \
		--output text) && \
	AWS_PROFILE=admin aws ssm start-associations-once --association-ids $$ASSOC_ID --region us-west-2 && \
	echo "CloudWatch Agent configuration re-applied"

build: ## Build Docker image locally
	docker build -t thrive-exercise:local -f app/Dockerfile app

run: ## Run Docker image locally (no AWS required)
	docker run --rm \
		-e SECRET_KEY_BASE=$$(openssl rand -hex 64) \
		-p 3000:80 \
		thrive-exercise:local
