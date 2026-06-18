.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help test test-file lint install install-project status uninstall

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

test: ## Run the full bats suite
	bats tests/

test-file: ## Run one test file: make test-file FILE=tests/confidence.bats
	bats $(FILE)

lint: ## Syntax-check the installer, hooks, and scripts
	bash -n ai-native-workflow
	@for f in hooks/*.sh scripts/*.sh skills/*/*.bash; do \
		[ -e "$$f" ] && bash -n "$$f" || true; \
	done
	@echo "lint OK"

install: ## Install the harness globally (~/.claude + ~/.copilot)
	./ai-native-workflow install global

install-project: ## Install per-project hooks into DIR (default: .)
	./ai-native-workflow install project $(or $(DIR),.)

status: ## Show what is installed
	./ai-native-workflow status

uninstall: ## Remove the global harness
	./ai-native-workflow uninstall global
