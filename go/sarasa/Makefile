# Sarasa Makefile
# Automated global package manager upgrades

BINARY_NAME := sarasa
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build flags
LDFLAGS := -ldflags "-s -w \
	-X github.com/indrasvat/sarasa/cmd.Version=$(VERSION) \
	-X github.com/indrasvat/sarasa/cmd.Commit=$(COMMIT) \
	-X github.com/indrasvat/sarasa/cmd.BuildDate=$(BUILD_DATE)"

# Go parameters
GOCMD := go
GOBUILD := $(GOCMD) build
GOCLEAN := $(GOCMD) clean
GOTEST := $(GOCMD) test
GOGET := $(GOCMD) get
GOMOD := $(GOCMD) mod
GOVET := $(GOCMD) vet

# Directories
INSTALL_DIR := $(HOME)/.local/bin

.PHONY: all build clean test lint lint-fix install uninstall deps tidy fmt vet help

## Build the binary
all: build

## Build the binary
build:
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME) .

## Build for release (all platforms)
build-all: build-darwin-arm64 build-darwin-amd64 build-linux-amd64

build-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME)-darwin-arm64 .

build-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME)-darwin-amd64 .

build-linux-amd64:
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME)-linux-amd64 .

## Clean build artifacts
clean:
	$(GOCLEAN)
	rm -f $(BINARY_NAME)
	rm -f $(BINARY_NAME)-*

## Run tests
test:
	$(GOTEST) -v -race ./...

## Run tests with coverage
test-coverage:
	$(GOTEST) -v -race -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out -o coverage.html

## Run linter (golangci-lint v2)
lint:
	@if [ -f ./golangci-lint ]; then \
		./golangci-lint run ./...; \
	elif command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not installed. Run 'make install-lint' to install."; \
		exit 1; \
	fi

## Run linter with auto-fix
lint-fix:
	@if [ -f ./golangci-lint ]; then \
		./golangci-lint run --fix ./...; \
	elif command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run --fix ./...; \
	else \
		echo "golangci-lint not installed. Run 'make install-lint' to install."; \
		exit 1; \
	fi

## Install golangci-lint v2
install-lint:
	curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b . v2.8.0

## Run go vet
vet:
	$(GOVET) ./...

## Format code
fmt:
	$(GOCMD) fmt ./...
	@if command -v goimports >/dev/null 2>&1; then \
		goimports -w .; \
	fi

## Download dependencies
deps:
	$(GOGET) -v ./...

## Tidy go.mod
tidy:
	$(GOMOD) tidy

## Install binary to ~/.local/bin
install: build
	@mkdir -p $(INSTALL_DIR)
	@cp $(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@chmod +x $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to $(INSTALL_DIR)"

## Uninstall binary from ~/.local/bin
uninstall:
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Uninstalled $(BINARY_NAME) from $(INSTALL_DIR)"

## Install development tools
dev-tools:
	@echo "Installing development tools..."
	@brew install golangci-lint 2>/dev/null || echo "golangci-lint already installed or brew not available"
	@go install golang.org/x/tools/cmd/goimports@latest

## Run all checks (fmt, vet, lint, test)
check: fmt vet lint test

## Show version information
version:
	@echo "Version: $(VERSION)"
	@echo "Commit: $(COMMIT)"
	@echo "Build Date: $(BUILD_DATE)"

## Show help
help:
	@echo "Sarasa - Automated global package manager upgrades"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*' $(MAKEFILE_LIST) | grep -v '^##' | awk -F':' '{print "  " $$1}'
