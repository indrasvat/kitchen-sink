.PHONY: help install install-shell install-python install-go uninstall lint lint-shell lint-python lint-go list ci test hooks tools tools-ci

SHELL := /bin/bash
BIN_DIR := $(HOME)/.local/bin

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

help: ## Show this help
	@echo ""
	@echo -e "$(CYAN)kitchen-sink$(NC) - Script collection management"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

install: hooks install-shell install-python install-go ## Install all scripts to ~/.local/bin
	@echo -e "$(GREEN)✓$(NC) All scripts installed to $(BIN_DIR)"

install-shell: ## Install shell scripts
	@mkdir -p $(BIN_DIR)
	@echo "Installing shell scripts..."
	@ln -sf $(CURDIR)/shell/screenshot-tools/iterm2-screenshot.sh $(BIN_DIR)/iterm2-screenshot
	@ln -sf $(CURDIR)/shell/screenshot-tools/tmux-screenshot.sh $(BIN_DIR)/tmux-screenshot
	@ln -sf $(CURDIR)/shell/screenshot-tools/zellij-screenshot.sh $(BIN_DIR)/zellij-screenshot
	@ln -sf $(CURDIR)/shell/utilities/upgrade-ai-cli.sh $(BIN_DIR)/upgrade-ai-cli
	@ln -sf $(CURDIR)/shell/utilities/watch-and-notify.sh $(BIN_DIR)/watch-and-notify
	@ln -sf $(CURDIR)/shell/dev-setup/gameboy-dev-setup-macos.sh $(BIN_DIR)/gameboy-dev-setup
	@echo -e "  $(GREEN)✓$(NC) Shell scripts linked"

install-python: ## Install Python scripts
	@mkdir -p $(BIN_DIR)
	@echo "Installing Python scripts..."
	@ln -sf $(CURDIR)/python/dev-tools/process-lister.py $(BIN_DIR)/process-lister
	@ln -sf $(CURDIR)/python/dev-tools/github-issue-importer.py $(BIN_DIR)/github-issue-importer
	@ln -sf $(CURDIR)/python/dev-tools/pyproject-dependencies-graph.py $(BIN_DIR)/pyproject-deps-graph
	@ln -sf $(CURDIR)/python/automation/ntp.py $(BIN_DIR)/ntp-time
	@ln -sf $(CURDIR)/python/games/space-war.py $(BIN_DIR)/space-war
	@echo -e "  $(GREEN)✓$(NC) Python scripts linked"

install-go: ## Build and install Go tools
	@mkdir -p $(BIN_DIR)
	@echo "Building Go tools..."
	@cd $(CURDIR)/go/sarasa && go build -o $(BIN_DIR)/sarasa .
	@echo -e "  $(GREEN)✓$(NC) Go tools built and installed"

uninstall: ## Remove installed scripts from ~/.local/bin
	@echo "Removing installed scripts..."
	@rm -f $(BIN_DIR)/iterm2-screenshot
	@rm -f $(BIN_DIR)/tmux-screenshot
	@rm -f $(BIN_DIR)/zellij-screenshot
	@rm -f $(BIN_DIR)/upgrade-ai-cli
	@rm -f $(BIN_DIR)/watch-and-notify
	@rm -f $(BIN_DIR)/gameboy-dev-setup
	@rm -f $(BIN_DIR)/process-lister
	@rm -f $(BIN_DIR)/github-issue-importer
	@rm -f $(BIN_DIR)/pyproject-deps-graph
	@rm -f $(BIN_DIR)/ntp-time
	@rm -f $(BIN_DIR)/space-war
	@rm -f $(BIN_DIR)/sarasa
	@echo -e "$(GREEN)✓$(NC) Scripts removed"

lint: lint-shell lint-python lint-go ## Run all linters

lint-shell: ## Lint shell scripts with shellcheck
	@echo "Linting shell scripts..."
	@shellcheck shell/**/*.sh
	@echo -e "  $(GREEN)✓$(NC) Shell lint passed"

lint-python: ## Lint Python scripts with ruff
	@echo "Linting Python scripts..."
	@uv run ruff check python/
	@echo -e "  $(GREEN)✓$(NC) Python lint passed"

lint-go: ## Lint Go code with golangci-lint
	@echo "Linting Go code..."
	@cd $(CURDIR)/go/sarasa && $(MAKE) lint
	@echo -e "  $(GREEN)✓$(NC) Go lint passed"

list: ## List all available scripts
	@echo ""
	@echo -e "$(CYAN)Shell Scripts$(NC)"
	@echo "  screenshot-tools/"
	@ls -1 shell/screenshot-tools/*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^/    /'
	@echo "  utilities/"
	@ls -1 shell/utilities/*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^/    /'
	@echo "  dev-setup/"
	@ls -1 shell/dev-setup/*.sh 2>/dev/null | xargs -I{} basename {} .sh | sed 's/^/    /'
	@echo ""
	@echo -e "$(CYAN)Python Scripts$(NC)"
	@echo "  automation/"
	@ls -1 python/automation/*.py 2>/dev/null | xargs -I{} basename {} .py | sed 's/^/    /'
	@echo "  dev-tools/"
	@ls -1 python/dev-tools/*.py 2>/dev/null | xargs -I{} basename {} .py | sed 's/^/    /'
	@echo "  games/"
	@ls -1 python/games/*.py 2>/dev/null | xargs -I{} basename {} .py | sed 's/^/    /'
	@echo ""
	@echo -e "$(CYAN)Go Tools$(NC)"
	@echo "    sarasa - Automated global package manager upgrades"
	@echo ""

ci: lint test ## Run all lints and tests (used by pre-push hook)
	@echo -e "$(GREEN)✓ All CI checks passed$(NC)"

test: ## Run all tests
	@echo "Running Go tests..."
	@cd $(CURDIR)/go/sarasa && $(MAKE) test
	@echo -e "  $(GREEN)✓$(NC) Go tests passed"

hooks: ## Install git hooks via lefthook
	@if command -v lefthook >/dev/null 2>&1; then \
		lefthook install; \
		echo -e "$(GREEN)✓$(NC) Git hooks installed via lefthook"; \
	else \
		echo -e "$(YELLOW)⚠$(NC)  lefthook not found. Install with:"; \
		echo "    brew install lefthook"; \
		echo "  Then run 'make hooks' to install git hooks."; \
	fi

tools: ## Install development tools (macOS)
	@echo "Checking development tools..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "  Installing shellcheck..."; brew install shellcheck; }
	@command -v uv >/dev/null 2>&1 || { echo "  Installing uv..."; brew install uv; }
	@command -v go >/dev/null 2>&1 || { echo "  Installing go..."; brew install go; }
	@command -v golangci-lint >/dev/null 2>&1 || { echo "  Installing golangci-lint..."; go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.1.6; }
	@command -v lefthook >/dev/null 2>&1 || { echo "  Installing lefthook..."; go install github.com/evilmartians/lefthook@latest; }
	@echo -e "$(GREEN)✓$(NC) All tools available"
	@echo ""
	@echo "Versions:"
	@echo -n "  shellcheck: " && shellcheck --version | head -2 | tail -1
	@echo -n "  uv: " && uv --version
	@echo -n "  go: " && go version | cut -d' ' -f3
	@echo -n "  golangci-lint: " && golangci-lint --version | cut -d' ' -f4
	@echo -n "  lefthook: " && lefthook version

tools-ci: ## Install CI tools (Go only)
	@echo "Installing CI tools..."
	@go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.1.6
	@echo -e "$(GREEN)✓$(NC) CI tools installed"
