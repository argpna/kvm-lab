# Lab entry point. Select hosts with GROUP=<group|host1,host2|pattern> (default: all hosts).
SHELL := bash
export PATH := $(CURDIR)/.venv/bin:$(PATH)

GROUP ?= all
JOBS  ?= 4
INV   := inventory/inventory.py
HOSTS := $(shell ansible all -i $(INV) -l '$(GROUP)' --list-hosts 2>/dev/null | tail -n +2 | tr -d ' ')

.PHONY: help key networks up provision destroy status images-linux image-win2019 image-win2022

help:
	@echo "make up GROUP=...        create VMs, wait until ready"
	@echo "make provision GROUP=... run playbooks/main.yml on the selected hosts"
	@echo "make destroy GROUP=...   delete VMs"
	@echo "make status              list lab VMs"

key:
	@test -f .lab/ssh/id_ed25519 || { mkdir -p .lab/ssh && ssh-keygen -q -t ed25519 -N '' -C kvm-lab -f .lab/ssh/id_ed25519; }

networks:
	@test -n "$(HOSTS)" || { echo "no hosts match GROUP=$(GROUP)" >&2; exit 1; }
	@nets=$$(for h in $(HOSTS); do $(INV) --host $$h | jq -r '.attached_networks[]'; done | sort -u | jq -R . | jq -sc .); \
	  ansible-playbook playbooks/libvirt-host-network.yml -e "{\"libvirt_host_network_names\": $$nets}"

up: key networks
	@printf '%s\n' $(HOSTS) | xargs -P $(JOBS) -I{} scripts/lab-vm.sh up {}
	ansible-playbook playbooks/lab-ready.yml -l '$(GROUP)'

provision:
	ansible-playbook playbooks/main.yml -l '$(GROUP)' $(ANSIBLE_EXTRA_ARGS)

destroy:
	@test -n "$(HOSTS)" || { echo "no hosts match GROUP=$(GROUP)" >&2; exit 1; }
	@printf '%s\n' $(HOSTS) | xargs -P $(JOBS) -I{} scripts/lab-vm.sh destroy {}

status:
	@virsh -c qemu:///system list --all | grep -E ' Name |lab-' || true

images-linux:
	scripts/fetch-linux-images.sh $(IMAGES)

image-win2019 image-win2022:
	scripts/build-windows-image.sh $(patsubst image-win%,%,$@)
