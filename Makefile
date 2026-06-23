# Conformer — dev tasks. Needs: docker (for HCL/patch tooling via the image),
# go (for the registry-api build). Build the image once with `make image`.

IMAGE ?= wecloudes/conformer:latest
DC    := docker compose -f compose/docker-compose.yml
# Run a shell command inside the image with the repo mounted (override the
# registry-api entrypoint).
RUN   := docker run --rm --entrypoint sh -v "$(CURDIR)":/repo -w /repo $(IMAGE) -c

.PHONY: help image fmt lint build test-rule test-transform

help: ## list targets
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*##' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

image: ## build the registry-api / toolkit image
	$(DC) build registry-api

fmt: ## format all patch HCL (*.mptf.hcl, *.tf under patches/)
	$(RUN) 'tofu fmt -recursive patches'

lint: ## syntax-check scripts + patch HCL + build the Go service
	bash -n scripts/*.sh compose/*.sh
	$(RUN) 'tofu fmt -check -recursive patches' || { echo ">> unformatted HCL — run: make fmt"; exit 1; }
	cd registry-api && go build ./...
	@echo "lint OK"

build: ## build the registry-api binary
	cd registry-api && go build -o /dev/null ./...

# Validate the current rule packs against a real upstream module.
#   make test-rule FW=cis_v600 NS=terraform-aws-modules MODULE=vpc PROVIDER=aws VERSION=5.13.0
test-rule: ## test rules vs a real module (FW= NS= MODULE= PROVIDER= VERSION=)
	$(RUN) 'bash /repo/scripts/test-rule.sh $(FW) $(NS) $(MODULE) $(PROVIDER) $(VERSION)'

# Validate an AD-HOC transformation set (no framework) against a real module.
#   make test-transform TR=tags,destroy NS=Azure MODULE=avm-res-automation-automationaccount PROVIDER=azurerm VERSION=0.2.0
test-transform: ## test a transformation set vs a real module (TR= NS= MODULE= PROVIDER= VERSION=)
	docker run --rm -e TRANSFORMATIONS=$(TR) --entrypoint sh -v "$(CURDIR)":/repo -w /repo $(IMAGE) \
	  -c 'bash /repo/scripts/test-rule.sh none $(NS) $(MODULE) $(PROVIDER) $(VERSION)'
