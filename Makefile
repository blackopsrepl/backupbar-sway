PREFIX ?= $(HOME)/.local
APP_HOME ?= $(PREFIX)/share/backupbar
BIN_DIR ?= $(PREFIX)/bin
CONFIG_PATH ?= $(HOME)/.config/backupbar/config.json
SOLVERFORGE_PATH ?= $(HOME)/.local/share/solverforge
RUBY ?= $(shell command -v ruby 2>/dev/null || printf '%s' /usr/bin/ruby)
QMLLINT ?= $(shell command -v qmllint 2>/dev/null || printf '%s' /usr/bin/qmllint)
QMLLINT_SUPPORTS_LEVELS := $(shell "$(QMLLINT)" --help 2>&1 | grep -q -- '--type <level>' && printf '%s' yes)

ifeq ($(QMLLINT_SUPPORTS_LEVELS),yes)
QMLLINT_DEFAULT_DIAGNOSTIC_ARGS := --import info --type info --property info --signal info --unqualified info
endif

QMLLINT_DIAGNOSTIC_ARGS ?= $(QMLLINT_DEFAULT_DIAGNOSTIC_ARGS)

.PHONY: help syntax test smoke qml-lint check install configure-user install-solverforge-linux-integration release-check

help:
	@printf '%s\n' \
		'BackupBar targets:' \
		'  syntax                                Validate Ruby and Bash syntax' \
		'  test                                  Run deterministic Ruby tests' \
		'  smoke                                 Exercise the CLI in an isolated state directory' \
		'  qml-lint                              Validate the QuickShell QML' \
		'  check                                 Run the full deterministic check' \
		'  install                               Install the application under ~/.local' \
		'  configure-user                        Create the user config when absent' \
		'  install-solverforge-linux-integration Install the Waybar wrapper' \
		'  release-check                         Alias for check'

syntax:
	@find bin lib test -type f -name '*.rb' -print -exec "$(RUBY)" -wc {} \;
	@bash -n packaging/solverforge-linux/solverforge-waybar-backupbar

test:
	@"$(RUBY)" test/run.rb

smoke:
	@"$(RUBY)" test/smoke.rb

qml-lint:
	@"$(QMLLINT)" $(QMLLINT_DIAGNOSTIC_ARGS) frontend/quickshell/shell.qml

check: syntax test smoke qml-lint

install:
	mkdir -p "$(APP_HOME)" "$(BIN_DIR)"
	cp -R bin lib frontend docs README.md WIREFRAME.md AGENTS.md Makefile packaging "$(APP_HOME)/"
	chmod +x "$(APP_HOME)/bin/backupbar"
	ln -sfn "$(APP_HOME)/bin/backupbar" "$(BIN_DIR)/backupbar"

configure-user: install
	@test -f "$(CONFIG_PATH)" || "$(BIN_DIR)/backupbar" config init --config "$(CONFIG_PATH)" >/dev/null

install-solverforge-linux-integration:
	mkdir -p "$(SOLVERFORGE_PATH)/bin"
	cp packaging/solverforge-linux/solverforge-waybar-backupbar "$(SOLVERFORGE_PATH)/bin/solverforge-waybar-backupbar"
	chmod +x "$(SOLVERFORGE_PATH)/bin/solverforge-waybar-backupbar"

release-check: check
