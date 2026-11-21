# Dev tasks. Lab operations are in scripts/lab (run "lab help").
SHELL := bash
export PATH := $(CURDIR)/.venv/bin:$(PATH)

.PHONY: lint

lint:
	ansible-lint
	shellcheck bootstrap/*.sh scripts/*.sh scripts/lab
	tofu fmt -check -recursive tofu
	tofu -chdir=tofu validate
