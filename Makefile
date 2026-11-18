# Lab entry point. Select hosts with LIMIT=<group|host1,host2|pattern> (default: all hosts).
SHELL := bash
export PATH := $(CURDIR)/.venv/bin:$(PATH)

LIMIT ?= all
JOBS  ?= 4
INV   := inventory/inventory.py
HOSTS := $(shell ansible all -i $(INV) -l '$(LIMIT)' --list-hosts 2>/dev/null | tail -n +2 | tr -d ' ')

.PHONY: help key networks up provision stop destroy status lint

help:
	@echo "make up LIMIT=...        create VMs, wait until ready"
	@echo "make provision LIMIT=... run playbooks/main.yml on the selected hosts"
	@echo "make stop LIMIT=...      shut VMs down, keep their disks (FORCE=1 powers off)"
	@echo "make destroy LIMIT=...   delete VMs"
	@echo "make status              list lab VMs"
	@echo "make lint                ansible-lint, shellcheck, tofu fmt and validate"

key:
	@test -f .lab/ssh/id_ed25519 || { mkdir -p .lab/ssh && ssh-keygen -q -t ed25519 -N '' -C kvm-lab -f .lab/ssh/id_ed25519; }

networks:
	@test -n "$(HOSTS)" || { echo "no hosts match LIMIT=$(LIMIT) (run lab hosts to list hosts and groups)" >&2; exit 1; }
	@nets=$$(for h in $(HOSTS); do $(INV) --host $$h | jq -r '.attached_networks[]'; done | sort -u | jq -R . | jq -sc .); \
	  ansible-playbook playbooks/libvirt-host-network.yml -e "{\"libvirt_host_network_names\": $$nets}"

up: key networks
	@printf '%s\n' $(HOSTS) | xargs -P $(JOBS) -I{} scripts/lab-vm.sh up {}
	ansible-playbook playbooks/lab-ready.yml -l '$(LIMIT)'

provision:
	ansible-playbook playbooks/main.yml -l '$(LIMIT)' $(ANSIBLE_EXTRA_ARGS)

stop:
	@test -n "$(HOSTS)" || { echo "no hosts match LIMIT=$(LIMIT) (run lab hosts to list hosts and groups)" >&2; exit 1; }
	@printf '%s\n' $(HOSTS) | FORCE=$(FORCE) xargs -P $(JOBS) -I{} scripts/lab-vm.sh stop {}

destroy:
	@test -n "$(HOSTS)" || { echo "no hosts match LIMIT=$(LIMIT) (run lab hosts to list hosts and groups)" >&2; exit 1; }
	@printf '%s\n' $(HOSTS) | xargs -P $(JOBS) -I{} scripts/lab-vm.sh destroy {}

status:
	@virsh -c qemu:///system list --all | grep -E ' Name |lab-' || true

lint:
	ansible-lint
	shellcheck bootstrap/*.sh scripts/*.sh
	tofu fmt -check -recursive tofu
	tofu -chdir=tofu validate
