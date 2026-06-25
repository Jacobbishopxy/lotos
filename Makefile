# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

.DEFAULT_GOAL := help

MDBOOK_DIR ?= docs/book/lotos
MDBOOK_HOST ?= 0.0.0.0
MDBOOK_PORT ?= 3004
DASHBOARD_DIR ?= applications/dashboard
DASHBOARD_HOST ?= 127.0.0.1
DASHBOARD_API_TARGET ?= http://127.0.0.1:8081
DASHBOARD_API_ROOT ?= /SimpleServer
DASHBOARD_API_BASE ?=
DASHBOARD_API_TIMEOUT_MS ?= 3500
DASHBOARD_BRIDGE_TARGET ?= http://127.0.0.1:8090
DASHBOARD_BRIDGE_PATH ?= /submit
DASHBOARD_BRIDGE_BASE ?=
DASHBOARD_BRIDGE_TIMEOUT_MS ?= 10000
TASKSCHEDULE_CONFIG_DIR ?= applications/TaskSchedule/config
TASKSCHEDULE_BROKER_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/broker.json
TASKSCHEDULE_WORKER_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/worker.json
TASKSCHEDULE_CLIENT_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/client.json
TASKSCHEDULE_CLIENT_BRIDGE_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/client-bridge.json
TASKSCHEDULE_TASK_TOML ?= $(TASKSCHEDULE_CONFIG_DIR)/task-demo.toml
TASKSCHEDULE_TASK_TEMPLATE_OUT ?= tasks/task-template.toml
TASKSCHEDULE_RELEASE_DIR ?= dist-release/TaskSchedule
TASKSCHEDULE_BIND_ALL ?= 0
TASKSCHEDULE_BIND_HOST ?= 0.0.0.0
TASKSCHEDULE_CONNECT_HOST ?= 127.0.0.1
TASKSCHEDULE_DASHBOARD_ORIGIN_HOST ?= $(TASKSCHEDULE_CONNECT_HOST)
TASKSCHEDULE_BIND_ALL_CONFIG_DIR ?= .tmp/task-schedule-bind-all-config
TASKSCHEDULE_BIND_ALL_ENABLED := $(filter 1 true yes on,$(TASKSCHEDULE_BIND_ALL))
TASKSCHEDULE_EFFECTIVE_BROKER_CONFIG = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)/broker.json,$(TASKSCHEDULE_BROKER_CONFIG))
TASKSCHEDULE_EFFECTIVE_WORKER_CONFIG = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)/worker.json,$(TASKSCHEDULE_WORKER_CONFIG))
TASKSCHEDULE_EFFECTIVE_CLIENT_CONFIG = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)/client.json,$(TASKSCHEDULE_CLIENT_CONFIG))
TASKSCHEDULE_EFFECTIVE_CLIENT_BRIDGE_CONFIG = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)/client-bridge.json,$(TASKSCHEDULE_CLIENT_BRIDGE_CONFIG))
TASKSCHEDULE_CONFIG_PROFILE_PREREQ = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),task-schedule-bind-all-config,)
DASHBOARD_EFFECTIVE_HOST = $(if $(TASKSCHEDULE_BIND_ALL_ENABLED),$(TASKSCHEDULE_BIND_HOST),$(DASHBOARD_HOST))

CI_TEST_TARGETS ?= \
	lotos:test:test-conc-executor \
	lotos:test:test-zmq-worker-frames \
	lotos:test:test-zmq-client-ack-frames \
	lotos:test:test-zmq-worker-wake \
	lotos:test:test-zmq-capacity-reservations \
	lotos:test:test-zmq-log-protocol-config \
	lotos:test:test-zmq-log-ingest \
	lotos:test:test-zmq-worker-log-transport \
	TaskSchedule:test:test-worker-lifecycle \
	TaskSchedule:test:test-scheduler \
	TaskSchedule:test:test-client-submission \
	TaskSchedule:test:test-client-bridge \
	lotos-minimal-scheduler-example:test:test-minimal-scheduler-example

.PHONY: help tree clean update build ci-build ci-test ci-docs ci-check book-build book-serve docs-build docs-serve dashboard-install dashboard-build dashboard-dev dashboard-preview task-schedule-build-server task-schedule-build-worker task-schedule-build-client task-schedule-build-client-bridge task-schedule-build-all task-schedule-bind-all-config release-clean release-server release-worker release-client release-client-bridge release-task-schedule release-manifest task-schedule-server task-schedule-broker task-schedule-worker task-schedule-client-bridge task-schedule-submit task-submit task-validate task-template example-minimal smoke-single smoke-multi smoke-dashboard-bridge smoke-dashboard-browser hie

help:
	@printf '%s\n' 'Lotos Make targets:'
	@printf '  %-24s %s\n' 'help' 'Show this help (default target).'
	@printf '  %-24s %s\n' 'tree' 'Print repository tree using .gitignore rules.'
	@printf '  %-24s %s\n' 'clean' 'Run cabal clean.'
	@printf '  %-24s %s\n' 'update' 'Run cabal update.'
	@printf '  %-24s %s\n' 'build' 'Build all workspace components.'
	@printf '  %-24s %s\n' 'ci-build' 'Build all components with tests enabled.'
	@printf '  %-24s %s\n' 'ci-test' 'Run bounded regression suites in CI_TEST_TARGETS.'
	@printf '  %-24s %s\n' 'ci-docs' 'Build documentation via book-build.'
	@printf '  %-24s %s\n' 'ci-check' 'Run ci-build, ci-test, and ci-docs.'
	@printf '  %-24s %s\n' 'book-build' 'Build mdBook from MDBOOK_DIR.'
	@printf '  %-24s %s\n' 'book-serve' 'Serve mdBook on MDBOOK_HOST:MDBOOK_PORT.'
	@printf '  %-24s %s\n' 'docs-build' 'Alias for book-build.'
	@printf '  %-24s %s\n' 'docs-serve' 'Alias for book-serve.'
	@printf '  %-24s %s\n' 'dashboard-install' 'Install dashboard npm dependencies.'
	@printf '  %-24s %s\n' 'dashboard-build' 'Build the dashboard Vite app (no live server required).'
	@printf '  %-24s %s\n' 'dashboard-dev' 'Run Vite dashboard on DASHBOARD_HOST with read API and submit bridge proxies.'
	@printf '  %-24s %s\n' 'dashboard-preview' 'Preview the built dashboard locally.'
	@printf '  %-24s %s\n' 'task-schedule-build-server' 'Build TaskSchedule ts-server executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-worker' 'Build TaskSchedule ts-worker executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-client' 'Build TaskSchedule ts-client executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-client-bridge' 'Build TaskSchedule ts-client-bridge executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-all' 'Build all TaskSchedule role executables.'
	@printf '  %-24s %s\n' 'task-schedule-bind-all-config' 'Generate .tmp configs for TASKSCHEDULE_BIND_ALL=1 public binds.'
	@printf '  %-24s %s\n' 'release-clean' 'Remove TASKSCHEDULE_RELEASE_DIR.'
	@printf '  %-24s %s\n' 'release-server' 'Package ts-server plus broker config into TASKSCHEDULE_RELEASE_DIR.'
	@printf '  %-24s %s\n' 'release-worker' 'Package ts-worker plus worker config into TASKSCHEDULE_RELEASE_DIR.'
	@printf '  %-24s %s\n' 'release-client' 'Package ts-client plus client config and sample task into TASKSCHEDULE_RELEASE_DIR.'
	@printf '  %-24s %s\n' 'release-client-bridge' 'Package ts-client-bridge plus bridge config into TASKSCHEDULE_RELEASE_DIR.'
	@printf '  %-24s %s\n' 'release-task-schedule' 'Package all TaskSchedule role binaries/configs/tasks with checksums.'
	@printf '  %-24s %s\n' 'task-schedule-server' 'Run long-lived TaskSchedule broker/server using TASKSCHEDULE_BROKER_CONFIG.'
	@printf '  %-24s %s\n' 'task-schedule-broker' 'Alias for task-schedule-server.'
	@printf '  %-24s %s\n' 'task-schedule-worker' 'Run long-lived TaskSchedule worker using TASKSCHEDULE_WORKER_CONFIG.'
	@printf '  %-24s %s\n' 'task-schedule-client-bridge' 'Run local dashboard submit bridge using TASKSCHEDULE_CLIENT_BRIDGE_CONFIG.'
	@printf '  %-24s %s\n' 'task-schedule-submit' 'Submit TASKSCHEDULE_TASK_TOML using TASKSCHEDULE_CLIENT_CONFIG.'
	@printf '  %-24s %s\n' 'task-submit' 'Alias for task-schedule-submit; override TASKSCHEDULE_TASK_TOML.'
	@printf '  %-24s %s\n' 'task-validate' 'Validate TASKSCHEDULE_TASK_TOML without contacting the broker.'
	@printf '  %-24s %s\n' 'task-template' 'Copy sample task TOML to TASKSCHEDULE_TASK_TEMPLATE_OUT.'
	@printf '  %-24s %s\n' 'example-minimal' 'Run the bounded minimal scheduler preview.'
	@printf '  %-24s %s\n' 'smoke-single' 'Run single-worker TaskSchedule smoke.'
	@printf '  %-24s %s\n' 'smoke-multi' 'Run multi-worker/capacity TaskSchedule smoke.'
	@printf '  %-24s %s\n' 'smoke-dashboard-bridge' 'Run server+worker+bridge+dashboard submit smoke with .tmp evidence.'
	@printf '  %-24s %s\n' 'smoke-dashboard-browser' 'Run smoke-dashboard-bridge plus real browser click automation (requires BROWSER_BIN or Chrome/Chromium on PATH).'
	@printf '  %-24s %s\n' 'hie' 'Regenerate hie.yaml with gen-hie.'
	@printf '\nmdBook defaults: MDBOOK_DIR=%s MDBOOK_HOST=%s MDBOOK_PORT=%s\n' '$(MDBOOK_DIR)' '$(MDBOOK_HOST)' '$(MDBOOK_PORT)'
	@printf 'Dashboard defaults: DASHBOARD_DIR=%s DASHBOARD_HOST=%s DASHBOARD_API_TARGET=%s DASHBOARD_API_ROOT=%s DASHBOARD_API_BASE=%s DASHBOARD_API_TIMEOUT_MS=%s DASHBOARD_BRIDGE_TARGET=%s DASHBOARD_BRIDGE_PATH=%s DASHBOARD_BRIDGE_BASE=%s DASHBOARD_BRIDGE_TIMEOUT_MS=%s\n' '$(DASHBOARD_DIR)' '$(DASHBOARD_HOST)' '$(DASHBOARD_API_TARGET)' '$(DASHBOARD_API_ROOT)' '$(DASHBOARD_API_BASE)' '$(DASHBOARD_API_TIMEOUT_MS)' '$(DASHBOARD_BRIDGE_TARGET)' '$(DASHBOARD_BRIDGE_PATH)' '$(DASHBOARD_BRIDGE_BASE)' '$(DASHBOARD_BRIDGE_TIMEOUT_MS)'
	@printf 'TaskSchedule defaults: TASKSCHEDULE_BROKER_CONFIG=%s TASKSCHEDULE_WORKER_CONFIG=%s TASKSCHEDULE_CLIENT_CONFIG=%s TASKSCHEDULE_CLIENT_BRIDGE_CONFIG=%s TASKSCHEDULE_TASK_TOML=%s TASKSCHEDULE_TASK_TEMPLATE_OUT=%s TASKSCHEDULE_RELEASE_DIR=%s\n' '$(TASKSCHEDULE_BROKER_CONFIG)' '$(TASKSCHEDULE_WORKER_CONFIG)' '$(TASKSCHEDULE_CLIENT_CONFIG)' '$(TASKSCHEDULE_CLIENT_BRIDGE_CONFIG)' '$(TASKSCHEDULE_TASK_TOML)' '$(TASKSCHEDULE_TASK_TEMPLATE_OUT)' '$(TASKSCHEDULE_RELEASE_DIR)'
	@printf 'Public bind flag: TASKSCHEDULE_BIND_ALL=%s TASKSCHEDULE_BIND_HOST=%s TASKSCHEDULE_CONNECT_HOST=%s TASKSCHEDULE_DASHBOARD_ORIGIN_HOST=%s TASKSCHEDULE_BIND_ALL_CONFIG_DIR=%s\n' '$(TASKSCHEDULE_BIND_ALL)' '$(TASKSCHEDULE_BIND_HOST)' '$(TASKSCHEDULE_CONNECT_HOST)' '$(TASKSCHEDULE_DASHBOARD_ORIGIN_HOST)' '$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)'

tree:
	tree . --gitignore

clean:
	cabal clean

update:
	cabal update

build:
	cabal build all

ci-build:
	cabal build all --enable-tests

ci-test:
	@set -e; \
	for target in $(CI_TEST_TARGETS); do \
		echo "==> cabal test $$target"; \
		cabal test $$target; \
	done

ci-docs: book-build

ci-check: ci-build ci-test ci-docs

book-build:
	mdbook build $(MDBOOK_DIR)

book-serve:
	mdbook serve $(MDBOOK_DIR) --hostname $(MDBOOK_HOST) --port $(MDBOOK_PORT)

docs-build: book-build

docs-serve: book-serve

dashboard-install:
	npm --prefix $(DASHBOARD_DIR) install

dashboard-build:
	VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" VITE_TASKSCHEDULE_BRIDGE_BASE="$(DASHBOARD_BRIDGE_BASE)" VITE_TASKSCHEDULE_BRIDGE_PATH="$(DASHBOARD_BRIDGE_PATH)" VITE_TASKSCHEDULE_BRIDGE_TIMEOUT_MS="$(DASHBOARD_BRIDGE_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run build

dashboard-dev:
	DASHBOARD_HOST="$(DASHBOARD_EFFECTIVE_HOST)" DASHBOARD_API_TARGET="$(DASHBOARD_API_TARGET)" DASHBOARD_BRIDGE_TARGET="$(DASHBOARD_BRIDGE_TARGET)" VITE_TASKSCHEDULE_API_TARGET="$(DASHBOARD_API_TARGET)" VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" VITE_TASKSCHEDULE_BRIDGE_BASE="$(DASHBOARD_BRIDGE_BASE)" VITE_TASKSCHEDULE_BRIDGE_PATH="$(DASHBOARD_BRIDGE_PATH)" VITE_TASKSCHEDULE_BRIDGE_TIMEOUT_MS="$(DASHBOARD_BRIDGE_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run dev

dashboard-preview:
	VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" VITE_TASKSCHEDULE_BRIDGE_BASE="$(DASHBOARD_BRIDGE_BASE)" VITE_TASKSCHEDULE_BRIDGE_PATH="$(DASHBOARD_BRIDGE_PATH)" VITE_TASKSCHEDULE_BRIDGE_TIMEOUT_MS="$(DASHBOARD_BRIDGE_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run preview

task-schedule-build-server:
	cabal build TaskSchedule:exe:ts-server

task-schedule-build-worker:
	cabal build TaskSchedule:exe:ts-worker

task-schedule-build-client:
	cabal build TaskSchedule:exe:ts-client

task-schedule-build-client-bridge:
	cabal build TaskSchedule:exe:ts-client-bridge

task-schedule-build-all: task-schedule-build-server task-schedule-build-worker task-schedule-build-client task-schedule-build-client-bridge

task-schedule-bind-all-config:
	scripts/task-schedule-config-profile.py \
		--source-dir "$(TASKSCHEDULE_CONFIG_DIR)" \
		--out-dir "$(TASKSCHEDULE_BIND_ALL_CONFIG_DIR)" \
		--bind-host "$(TASKSCHEDULE_BIND_HOST)" \
		--connect-host "$(TASKSCHEDULE_CONNECT_HOST)" \
		--dashboard-origin-host "$(TASKSCHEDULE_DASHBOARD_ORIGIN_HOST)"

release-clean:
	rm -rf $(TASKSCHEDULE_RELEASE_DIR)

release-server: task-schedule-build-server $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	@mkdir -p $(TASKSCHEDULE_RELEASE_DIR)/bin $(TASKSCHEDULE_RELEASE_DIR)/config
	@bin_path="$$(cabal list-bin TaskSchedule:exe:ts-server)"; \
		install -m 755 "$$bin_path" $(TASKSCHEDULE_RELEASE_DIR)/bin/ts-server
	install -m 644 $(TASKSCHEDULE_EFFECTIVE_BROKER_CONFIG) $(TASKSCHEDULE_RELEASE_DIR)/config/broker.json
	$(MAKE) release-manifest

release-worker: task-schedule-build-worker $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	@mkdir -p $(TASKSCHEDULE_RELEASE_DIR)/bin $(TASKSCHEDULE_RELEASE_DIR)/config
	@bin_path="$$(cabal list-bin TaskSchedule:exe:ts-worker)"; \
		install -m 755 "$$bin_path" $(TASKSCHEDULE_RELEASE_DIR)/bin/ts-worker
	install -m 644 $(TASKSCHEDULE_EFFECTIVE_WORKER_CONFIG) $(TASKSCHEDULE_RELEASE_DIR)/config/worker.json
	$(MAKE) release-manifest

release-client: task-schedule-build-client $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	@mkdir -p $(TASKSCHEDULE_RELEASE_DIR)/bin $(TASKSCHEDULE_RELEASE_DIR)/config $(TASKSCHEDULE_RELEASE_DIR)/tasks
	@bin_path="$$(cabal list-bin TaskSchedule:exe:ts-client)"; \
		install -m 755 "$$bin_path" $(TASKSCHEDULE_RELEASE_DIR)/bin/ts-client
	install -m 644 $(TASKSCHEDULE_EFFECTIVE_CLIENT_CONFIG) $(TASKSCHEDULE_RELEASE_DIR)/config/client.json
	install -m 644 $(TASKSCHEDULE_TASK_TOML) $(TASKSCHEDULE_RELEASE_DIR)/tasks/task-demo.toml
	$(MAKE) release-manifest

release-client-bridge: task-schedule-build-client-bridge $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	@mkdir -p $(TASKSCHEDULE_RELEASE_DIR)/bin $(TASKSCHEDULE_RELEASE_DIR)/config
	@bin_path="$$(cabal list-bin TaskSchedule:exe:ts-client-bridge)"; \
		install -m 755 "$$bin_path" $(TASKSCHEDULE_RELEASE_DIR)/bin/ts-client-bridge
	install -m 644 $(TASKSCHEDULE_EFFECTIVE_CLIENT_BRIDGE_CONFIG) $(TASKSCHEDULE_RELEASE_DIR)/config/client-bridge.json
	$(MAKE) release-manifest

release-task-schedule: release-server release-worker release-client release-client-bridge release-manifest

release-manifest:
	@if [ ! -d "$(TASKSCHEDULE_RELEASE_DIR)" ]; then \
		echo "release directory does not exist: $(TASKSCHEDULE_RELEASE_DIR)" >&2; \
		exit 1; \
	fi
	@cd $(TASKSCHEDULE_RELEASE_DIR) && \
		find . -type f ! -name MANIFEST.txt ! -name SHA256SUMS | sort > MANIFEST.txt && \
		if command -v sha256sum >/dev/null 2>&1; then \
			xargs sha256sum < MANIFEST.txt > SHA256SUMS; \
		elif command -v shasum >/dev/null 2>&1; then \
			xargs shasum -a 256 < MANIFEST.txt > SHA256SUMS; \
		else \
			echo "sha256sum or shasum is required to write SHA256SUMS" >&2; \
			exit 1; \
		fi
	@printf 'TaskSchedule release packaged at %s\n' '$(TASKSCHEDULE_RELEASE_DIR)'

task-schedule-server: $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	cabal run TaskSchedule:exe:ts-server -- $(TASKSCHEDULE_EFFECTIVE_BROKER_CONFIG)

task-schedule-broker: task-schedule-server

task-schedule-worker: $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	cabal run TaskSchedule:exe:ts-worker -- $(TASKSCHEDULE_EFFECTIVE_WORKER_CONFIG)

task-schedule-client-bridge: $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	cabal run TaskSchedule:exe:ts-client-bridge -- $(TASKSCHEDULE_EFFECTIVE_CLIENT_BRIDGE_CONFIG)

task-schedule-submit: $(TASKSCHEDULE_CONFIG_PROFILE_PREREQ)
	cabal run TaskSchedule:exe:ts-client -- $(TASKSCHEDULE_EFFECTIVE_CLIENT_CONFIG) $(TASKSCHEDULE_TASK_TOML)

task-submit: task-schedule-submit

task-validate:
	cabal run TaskSchedule:exe:ts-client -- --validate $(TASKSCHEDULE_TASK_TOML)

task-template:
	@mkdir -p "$$(dirname "$(TASKSCHEDULE_TASK_TEMPLATE_OUT)")"
	cp $(TASKSCHEDULE_CONFIG_DIR)/task-demo.toml $(TASKSCHEDULE_TASK_TEMPLATE_OUT)
	@printf 'Wrote task template: %s\n' '$(TASKSCHEDULE_TASK_TEMPLATE_OUT)'

example-minimal:
	cabal run lotos-minimal-scheduler-example:exe:mini-scheduler-preview

smoke-single:
	scripts/task-schedule-smoke.sh

smoke-multi:
	scripts/task-schedule-multi-worker-smoke.sh

smoke-dashboard-bridge:
	scripts/task-schedule-dashboard-bridge-smoke.sh

smoke-dashboard-browser:
	SMOKE_BROWSER_CLICK=1 scripts/task-schedule-dashboard-bridge-smoke.sh

hie:
	gen-hie > hie.yaml
