COMPOSE      = docker compose -f docker/compose-dev.yml
COMPOSE_TEST = docker compose -f docker/compose-test.yml
COMPOSE_DS   = docker compose -f docker/compose-dspace.yml
RUN          = $(COMPOSE) run --rm dev
RUN_TEST     = $(COMPOSE_TEST) run --rm test

.PHONY: help dev deps compile precommit test test.ci test.external dev.clean test.clean test.external.clean check

help: ## Show available targets
	@grep -E '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

dev: ## Drop into an interactive shell inside the dev container
	$(RUN) bash

deps: ## Install dependencies
	$(RUN) sh -c "mix deps.get && mix deps.compile"

compile: ## Compile the project
	$(RUN) mix compile

docs: ## Generate code documentation
	$(RUN) mix docs

precommit: ## Run code quality checks
	$(RUN_TEST) mix precommit

test: ## Run the test suite
	$(RUN_TEST) mix test

check: ## Run code audit
	$(RUN_TEST) mix check

test.ci: ## Run the test suite + mutation testing
	$(RUN_TEST) mix test.ci

test.external: ## Run the external tests against a bootstrapped DSpace instance
	$(COMPOSE_DS) -p dspace-ex-e2e up --wait --wait-timeout 600
	$(COMPOSE_TEST) -p dspace-ex-e2e run --rm \
		--env DSPACE_ENDPOINT=http://dspace:8080/server \
		--env DSPACE_ADMIN_EMAIL=admin@admin.com \
		--env DSPACE_ADMIN_PASSWORD=admin \
		test mix test --only external

dev.clean: ## Remove dev container and cached build volumes
	$(COMPOSE) down --volumes --remove-orphans

test.clean: ## Remove test container and cached build volumes
	$(COMPOSE_TEST) down --volumes --remove-orphans

test.external.clean: ## Stop and remove the external test DSpace stack
	$(COMPOSE_DS) -p dspace-ex-e2e down --volumes --remove-orphans
