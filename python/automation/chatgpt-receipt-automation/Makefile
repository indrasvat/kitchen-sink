# ══════════════════════════════════════════════════════════════════════════════
# ChatGPT Receipt Downloader - Makefile
# ══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   make              - Show help
#   make run          - Run the downloader now
#   make install      - Install as scheduled launchd job
#   make uninstall    - Remove the scheduled job
#   make status       - Check job status
#   make logs         - View recent logs
#   make tail         - Follow logs in real-time
#   make receipts     - Open receipts folder
#   make test         - Dry run to test the script
#
# ══════════════════════════════════════════════════════════════════════════════

SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help run install uninstall status logs tail receipts test clean check

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR := $(shell pwd)
PYTHON_SCRIPT := $(SCRIPT_DIR)/download_chatgpt_receipt.py
INSTALL_SCRIPT := $(SCRIPT_DIR)/install-launchd.sh

# Installed locations
SCRIPTS_DIR := $(HOME)/Scripts
LOGS_DIR := $(HOME)/Library/Logs/ChatGPTReceiptDownloader
RECEIPTS_DIR := $(HOME)/Documents/ChatGPT-Receipts
PLIST_DIR := $(HOME)/Library/LaunchAgents
PLIST_NAME := com.user.chatgpt-receipt.plist

# launchd job
JOB_LABEL := com.user.chatgpt-receipt
USER_ID := $(shell id -u)

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
BOLD := \033[1m
NC := \033[0m

# ──────────────────────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────────────────────

help: ## Show this help message
	@echo ""
	@echo -e "$(BOLD)ChatGPT Receipt Downloader$(NC)"
	@echo -e "$(CYAN)══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo -e "$(BOLD)Quick Start:$(NC)"
	@echo -e "  $(CYAN)make run$(NC)        Run the downloader now"
	@echo -e "  $(CYAN)make install$(NC)    Install as monthly scheduled job"
	@echo -e "  $(CYAN)make schedule$(NC)   Show schedule and next run times"
	@echo -e "  $(CYAN)make status$(NC)     Check job status"
	@echo ""
	@echo -e "$(BOLD)All Commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-14s$(NC) %s\n", $$1, $$2}'
	@echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Main Commands
# ──────────────────────────────────────────────────────────────────────────────

run: check ## Run the receipt downloader now
	@echo -e "$(BOLD)Running ChatGPT Receipt Downloader...$(NC)"
	@echo ""
	@uv run $(PYTHON_SCRIPT) \
		--provider bedrock \
		--profile "Profile 2" \
		--email-to "your-email@example.com"

run-auto: check ## Run without confirmation prompt (for automation)
	@echo -e "$(BOLD)Running ChatGPT Receipt Downloader (auto mode)...$(NC)"
	@echo ""
	@uv run $(PYTHON_SCRIPT) \
		--provider bedrock \
		--profile "Profile 2" \
		--email-to "your-email@example.com" \
		--auto

run-quiet: check ## Run quietly with minimal output
	@uv run $(PYTHON_SCRIPT) \
		--provider bedrock \
		--profile "Profile 2" \
		--email-to "your-email@example.com" \
		--auto \
		--quiet

# ──────────────────────────────────────────────────────────────────────────────
# Installation
# ──────────────────────────────────────────────────────────────────────────────

install: check ## Install as a scheduled launchd job
	@$(INSTALL_SCRIPT)

uninstall: ## Uninstall the scheduled job
	@echo -e "$(BOLD)Uninstalling ChatGPT Receipt Downloader...$(NC)"
	@echo ""
	@launchctl bootout gui/$(USER_ID)/$(JOB_LABEL) 2>/dev/null || true
	@rm -f $(PLIST_DIR)/$(PLIST_NAME)
	@rm -f $(SCRIPTS_DIR)/download_chatgpt_receipt.py
	@rm -f $(SCRIPTS_DIR)/run-chatgpt-receipt.sh
	@rm -f $(SCRIPTS_DIR)/chatgpt-receipt
	@echo -e "$(GREEN)✓$(NC) Uninstalled"
	@echo ""
	@echo "Logs and receipts were preserved:"
	@echo "  Logs:     $(LOGS_DIR)"
	@echo "  Receipts: $(RECEIPTS_DIR)"

reinstall: uninstall install ## Reinstall (uninstall then install)

# ──────────────────────────────────────────────────────────────────────────────
# Status & Monitoring
# ──────────────────────────────────────────────────────────────────────────────

status: ## Check job status and this month's receipt
	@echo -e "$(BOLD)ChatGPT Receipt Downloader - Status$(NC)"
	@echo "────────────────────────────────────────"
	@echo ""
	@if launchctl print gui/$(USER_ID)/$(JOB_LABEL) &>/dev/null; then \
		echo -e "Job status:    $(GREEN)Loaded$(NC)"; \
		STATUS=$$(launchctl print gui/$(USER_ID)/$(JOB_LABEL) 2>/dev/null); \
		LAST_EXIT=$$(echo "$$STATUS" | grep "last exit code" | awk '{print $$NF}'); \
		if [ -n "$$LAST_EXIT" ]; then \
			if [ "$$LAST_EXIT" = "0" ]; then \
				echo -e "Last exit:     $(GREEN)$$LAST_EXIT (success)$(NC)"; \
			else \
				echo -e "Last exit:     $(RED)$$LAST_EXIT (failed)$(NC)"; \
			fi \
		fi; \
		RUN_COUNT=$$(echo "$$STATUS" | grep "runs =" | awk '{print $$NF}'); \
		if [ -n "$$RUN_COUNT" ]; then \
			echo "Run count:     $$RUN_COUNT"; \
		fi \
	else \
		echo -e "Job status:    $(RED)Not loaded$(NC)"; \
		echo ""; \
		echo "Run 'make install' to set up the scheduled job."; \
	fi
	@echo ""
	@MONTH=$$(date +%Y-%m); \
	echo -e "$(BOLD)This month ($$MONTH):$(NC)"; \
	if [ -d "$(RECEIPTS_DIR)" ]; then \
		RECEIPT=$$(find $(RECEIPTS_DIR) -name "ChatGPT-Plus-Receipt-$$MONTH*.pdf" -type f 2>/dev/null | head -1); \
		if [ -n "$$RECEIPT" ]; then \
			echo -e "  Receipt:     $(GREEN)Downloaded$(NC)"; \
			echo "  File:        $$(basename $$RECEIPT)"; \
		else \
			echo -e "  Receipt:     $(YELLOW)Not yet downloaded$(NC)"; \
		fi \
	else \
		echo -e "  Receipt:     $(YELLOW)Receipts folder doesn't exist$(NC)"; \
	fi

schedule: ## Show schedule and next expected run
	@echo -e "$(BOLD)ChatGPT Receipt Downloader - Schedule$(NC)"
	@echo "────────────────────────────────────────"
	@echo ""
	@echo -e "$(BOLD)Schedule Configuration:$(NC)"
	@echo "  Trigger days:  28, 29, 30, 31"
	@echo "  Trigger time:  11:00 AM local time"
	@echo "  Late execution: Yes (runs when Mac wakes if missed)"
	@echo ""
	@echo -e "$(BOLD)Current Time:$(NC)"
	@echo "  $$(date '+%A, %B %d, %Y at %I:%M %p %Z')"
	@echo ""
	@echo -e "$(BOLD)Next Scheduled Runs:$(NC)"
	@TODAY_DAY=$$(date +%d); \
	TODAY_HOUR=$$(date +%H); \
	CURRENT_MONTH=$$(date +%m); \
	CURRENT_YEAR=$$(date +%Y); \
	NEXT_MONTH=$$(date -v+1m +%m); \
	NEXT_MONTH_YEAR=$$(date -v+1m +%Y); \
	FOUND=0; \
	for DAY in 28 29 30 31; do \
		if [ $$DAY -gt $$TODAY_DAY ] || ([ $$DAY -eq $$TODAY_DAY ] && [ $$TODAY_HOUR -lt 11 ]); then \
			DATE_STR=$$(date -j -f "%Y-%m-%d %H:%M" "$$CURRENT_YEAR-$$CURRENT_MONTH-$$DAY 11:00" "+%A, %B %d, %Y at 11:00 AM" 2>/dev/null); \
			if [ $$? -eq 0 ]; then \
				if [ $$FOUND -eq 0 ]; then \
					echo -e "  $(GREEN)→ $$DATE_STR$(NC)  (next)"; \
				else \
					echo "    $$DATE_STR"; \
				fi; \
				FOUND=$$((FOUND + 1)); \
			fi \
		fi \
	done; \
	for DAY in 28 29 30 31; do \
		DATE_STR=$$(date -j -f "%Y-%m-%d %H:%M" "$$NEXT_MONTH_YEAR-$$NEXT_MONTH-$$DAY 11:00" "+%A, %B %d, %Y at 11:00 AM" 2>/dev/null); \
		if [ $$? -eq 0 ]; then \
			if [ $$FOUND -eq 0 ]; then \
				echo -e "  $(GREEN)→ $$DATE_STR$(NC)  (next)"; \
			else \
				echo "    $$DATE_STR"; \
			fi; \
			FOUND=$$((FOUND + 1)); \
			if [ $$FOUND -ge 5 ]; then break; fi \
		fi \
	done
	@echo ""
	@echo -e "$(BOLD)How It Works:$(NC)"
	@echo "  The job is scheduled to run on days 28-31 because launchd"
	@echo "  doesn't support 'last day of month'. The script is idempotent -"
	@echo "  once it successfully downloads a receipt for a given month,"
	@echo "  subsequent runs that month will skip the download."
	@echo ""
	@if launchctl print gui/$(USER_ID)/$(JOB_LABEL) &>/dev/null; then \
		echo -e "Job status: $(GREEN)Loaded and active$(NC)"; \
	else \
		echo -e "Job status: $(RED)Not installed$(NC) - run 'make install'"; \
	fi

logs: ## View recent logs
	@echo -e "$(BOLD)Recent Logs$(NC)"
	@echo "────────────────────────────────────────"
	@echo ""
	@if [ -d "$(LOGS_DIR)" ]; then \
		LATEST=$$(ls -t $(LOGS_DIR)/run-*.log 2>/dev/null | head -1); \
		if [ -n "$$LATEST" ]; then \
			echo -e "$(CYAN)Latest: $$(basename $$LATEST)$(NC)"; \
			echo ""; \
			tail -50 "$$LATEST"; \
		else \
			LATEST=$$(ls -t $(LOGS_DIR)/*.log 2>/dev/null | head -1); \
			if [ -n "$$LATEST" ]; then \
				echo -e "$(CYAN)Latest: $$(basename $$LATEST)$(NC)"; \
				echo ""; \
				tail -50 "$$LATEST"; \
			else \
				echo "No logs found yet."; \
			fi \
		fi \
	else \
		echo "No logs directory found."; \
	fi

tail: ## Follow logs in real-time (Ctrl+C to stop)
	@echo -e "$(BOLD)Following logs (Ctrl+C to stop)...$(NC)"
	@echo ""
	@if [ -f "$(LOGS_DIR)/launchd-stdout.log" ]; then \
		tail -f $(LOGS_DIR)/launchd-stdout.log; \
	else \
		LATEST=$$(ls -t $(LOGS_DIR)/*.log 2>/dev/null | head -1); \
		if [ -n "$$LATEST" ]; then \
			tail -f "$$LATEST"; \
		else \
			echo "No log files found. Run 'make run' first."; \
		fi \
	fi

# ──────────────────────────────────────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────────────────────────────────────

receipts: ## Open receipts folder in Finder
	@mkdir -p $(RECEIPTS_DIR)
	@open $(RECEIPTS_DIR)
	@echo -e "$(BOLD)Receipts:$(NC)"
	@ls -la $(RECEIPTS_DIR)/*.pdf 2>/dev/null || echo "  (none yet)"

open-logs: ## Open logs folder in Finder
	@mkdir -p $(LOGS_DIR)
	@open $(LOGS_DIR)

test: check ## Test run with verbose output (doesn't send email)
	@echo -e "$(BOLD)Test Run (no email)$(NC)"
	@echo ""
	@uv run $(PYTHON_SCRIPT) \
		--provider bedrock \
		--profile "Profile 2"

# ──────────────────────────────────────────────────────────────────────────────
# launchd Job Control
# ──────────────────────────────────────────────────────────────────────────────

kickstart: ## Trigger the installed job via launchctl
	@if launchctl print gui/$(USER_ID)/$(JOB_LABEL) &>/dev/null; then \
		echo -e "$(BOLD)Triggering scheduled job...$(NC)"; \
		launchctl kickstart -p gui/$(USER_ID)/$(JOB_LABEL); \
		echo -e "$(GREEN)✓$(NC) Job started. Run 'make tail' to follow progress."; \
	else \
		echo -e "$(RED)Error:$(NC) Job not installed. Run 'make install' first."; \
		exit 1; \
	fi

stop: ## Stop a running job
	@launchctl kill SIGTERM gui/$(USER_ID)/$(JOB_LABEL) 2>/dev/null || \
		echo "No running job to stop."

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────

set-email: ## Change the email recipient (usage: make set-email EMAIL=new@example.com)
ifndef EMAIL
	@echo -e "$(RED)Error:$(NC) EMAIL not specified"
	@echo ""
	@echo "Usage: make set-email EMAIL=receipts@example.com"
	@echo ""
	@echo "Current email in installed plist:"
	@grep -A1 "email-to" $(PLIST_DIR)/$(PLIST_NAME) 2>/dev/null | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/  \1/' || echo "  (not installed)"
	@exit 1
endif
	@echo -e "$(BOLD)Updating email recipient to: $(EMAIL)$(NC)"
	@if [ -f "$(PLIST_DIR)/$(PLIST_NAME)" ]; then \
		sed -i '' 's|<string>robin\.sharma@ask\.com</string>|<string>$(EMAIL)</string>|g' "$(PLIST_DIR)/$(PLIST_NAME)"; \
		sed -i '' 's|<string>[^<]*@[^<]*</string>$$|<string>$(EMAIL)</string>|' "$(PLIST_DIR)/$(PLIST_NAME)"; \
		echo -e "$(GREEN)✓$(NC) Updated plist"; \
		launchctl bootout gui/$(USER_ID)/$(JOB_LABEL) 2>/dev/null || true; \
		launchctl bootstrap gui/$(USER_ID) "$(PLIST_DIR)/$(PLIST_NAME)"; \
		echo -e "$(GREEN)✓$(NC) Reloaded job"; \
		echo ""; \
		echo "New email recipient: $(EMAIL)"; \
	else \
		echo -e "$(RED)Error:$(NC) Job not installed. Run 'make install' first."; \
		exit 1; \
	fi

show-config: ## Show current configuration from installed plist
	@echo -e "$(BOLD)Installed Configuration$(NC)"
	@echo "────────────────────────────────────────"
	@if [ -f "$(PLIST_DIR)/$(PLIST_NAME)" ]; then \
		echo ""; \
		echo "Email recipient:"; \
		grep -A1 "email-to" "$(PLIST_DIR)/$(PLIST_NAME)" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/  \1/'; \
		echo ""; \
		echo "Chrome profile:"; \
		grep -A1 '">--profile<' "$(PLIST_DIR)/$(PLIST_NAME)" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/  \1/'; \
		echo ""; \
		echo "LLM provider:"; \
		grep -A1 '">--provider<' "$(PLIST_DIR)/$(PLIST_NAME)" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/  \1/'; \
		echo ""; \
		echo "AWS profile:"; \
		grep -A1 ">AWS_PROFILE<" "$(PLIST_DIR)/$(PLIST_NAME)" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/  \1/'; \
	else \
		echo -e "$(YELLOW)Job not installed.$(NC) Run 'make install' first."; \
	fi

# ──────────────────────────────────────────────────────────────────────────────
# Checks
# ──────────────────────────────────────────────────────────────────────────────

check: ## Verify prerequisites
	@command -v uv >/dev/null 2>&1 || { \
		echo -e "$(RED)Error:$(NC) 'uv' is not installed."; \
		echo "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"; \
		exit 1; \
	}
	@test -f $(PYTHON_SCRIPT) || { \
		echo -e "$(RED)Error:$(NC) Python script not found: $(PYTHON_SCRIPT)"; \
		exit 1; \
	}
	@if [ -z "$$AWS_PROFILE" ] && [ ! -f "$$HOME/.aws/credentials" ]; then \
		echo -e "$(YELLOW)Warning:$(NC) No AWS credentials found for Bedrock"; \
	fi

clean: ## Remove temporary files and caches
	@echo "Cleaning up..."
	@rm -rf __pycache__ .ruff_cache .mypy_cache
	@find . -name "*.pyc" -delete
	@find . -name ".DS_Store" -delete
	@echo -e "$(GREEN)✓$(NC) Cleaned"

reset-state: ## Clear state file (allows re-run this month)
	@echo -e "$(BOLD)Resetting state...$(NC)"
	@if [ -f "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json" ]; then \
		cat "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json"; \
		echo ""; \
		rm "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json"; \
		echo -e "$(GREEN)✓$(NC) State file removed"; \
		echo ""; \
		echo "Next run will download and email even if already done this month."; \
	else \
		echo "No state file found."; \
	fi

show-state: ## Show current state file contents
	@echo -e "$(BOLD)Current State$(NC)"
	@echo "────────────────────────────────────────"
	@if [ -f "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json" ]; then \
		cat "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json" | python3 -m json.tool 2>/dev/null || \
		cat "$(HOME)/Library/Application Support/ChatGPTReceiptDownloader/state.json"; \
	else \
		echo "(no state file - first run pending)"; \
	fi

# ──────────────────────────────────────────────────────────────────────────────
# Development
# ──────────────────────────────────────────────────────────────────────────────

lint: ## Run linter on Python script
	@uv run ruff check $(PYTHON_SCRIPT)

format: ## Format Python script
	@uv run ruff format $(PYTHON_SCRIPT)

info: ## Show configuration info
	@echo -e "$(BOLD)Configuration$(NC)"
	@echo "────────────────────────────────────────"
	@echo "Script dir:    $(SCRIPT_DIR)"
	@echo "Python script: $(PYTHON_SCRIPT)"
	@echo "Install dir:   $(SCRIPTS_DIR)"
	@echo "Logs dir:      $(LOGS_DIR)"
	@echo "Receipts dir:  $(RECEIPTS_DIR)"
	@echo "Job label:     $(JOB_LABEL)"
	@echo ""
	@echo -e "$(BOLD)uv:$(NC)"
	@which uv 2>/dev/null || echo "  Not found"
	@uv --version 2>/dev/null || true
	@echo ""
	@echo -e "$(BOLD)AWS:$(NC)"
	@echo "  AWS_PROFILE: $${AWS_PROFILE:-<not set>}"
