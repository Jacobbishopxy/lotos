# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

.DEFAULT_GOAL := help

MDBOOK_DIR ?= docs/book/lotos
MDBOOK_HOST ?= 0.0.0.0
MDBOOK_PORT ?= 3004
DASHBOARD_DIR ?= applications/dashboard
DASHBOARD_HOST ?= 0.0.0.0
DASHBOARD_API_TARGET ?= http://127.0.0.1:8081
DASHBOARD_API_ROOT ?= /SimpleServer
DASHBOARD_API_BASE ?=
DASHBOARD_API_TIMEOUT_MS ?= 3500
TASKSCHEDULE_CONFIG_DIR ?= applications/TaskSchedule/config
TASKSCHEDULE_BROKER_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/broker.json
TASKSCHEDULE_WORKER_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/worker.json
TASKSCHEDULE_CLIENT_CONFIG ?= $(TASKSCHEDULE_CONFIG_DIR)/client.json
TASKSCHEDULE_TASK_TOML ?= $(TASKSCHEDULE_CONFIG_DIR)/task-demo.toml
TASKSCHEDULE_TASK_TEMPLATE_OUT ?= tasks/task-template.toml

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
	lotos-minimal-scheduler-example:test:test-minimal-scheduler-example

.PHONY: help tree clean update build ci-build ci-test ci-docs ci-check book-build book-serve docs-build docs-serve dashboard-install dashboard-build dashboard-dev dashboard-preview task-schedule-build-server task-schedule-build-worker task-schedule-build-client task-schedule-build-all task-schedule-server task-schedule-broker task-schedule-worker task-schedule-submit task-submit task-validate task-template example-minimal smoke-single smoke-multi hie

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
	@printf '  %-24s %s\n' 'dashboard-dev' 'Run Vite dashboard on DASHBOARD_HOST with DASHBOARD_API_TARGET proxy.'
	@printf '  %-24s %s\n' 'dashboard-preview' 'Preview the built dashboard locally.'
	@printf '  %-24s %s\n' 'task-schedule-build-server' 'Build TaskSchedule ts-server executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-worker' 'Build TaskSchedule ts-worker executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-client' 'Build TaskSchedule ts-client executable.'
	@printf '  %-24s %s\n' 'task-schedule-build-all' 'Build all TaskSchedule role executables.'
	@printf '  %-24s %s\n' 'task-schedule-server' 'Run long-lived TaskSchedule broker/server using TASKSCHEDULE_BROKER_CONFIG.'
	@printf '  %-24s %s\n' 'task-schedule-broker' 'Alias for task-schedule-server.'
	@printf '  %-24s %s\n' 'task-schedule-worker' 'Run long-lived TaskSchedule worker using TASKSCHEDULE_WORKER_CONFIG.'
	@printf '  %-24s %s\n' 'task-schedule-submit' 'Submit TASKSCHEDULE_TASK_TOML using TASKSCHEDULE_CLIENT_CONFIG.'
	@printf '  %-24s %s\n' 'task-submit' 'Alias for task-schedule-submit; override TASKSCHEDULE_TASK_TOML.'
	@printf '  %-24s %s\n' 'task-validate' 'Validate TASKSCHEDULE_TASK_TOML without contacting the broker.'
	@printf '  %-24s %s\n' 'task-template' 'Copy sample task TOML to TASKSCHEDULE_TASK_TEMPLATE_OUT.'
	@printf '  %-24s %s\n' 'example-minimal' 'Run the bounded minimal scheduler preview.'
	@printf '  %-24s %s\n' 'smoke-single' 'Run single-worker TaskSchedule smoke.'
	@printf '  %-24s %s\n' 'smoke-multi' 'Run multi-worker/capacity TaskSchedule smoke.'
	@printf '  %-24s %s\n' 'hie' 'Regenerate hie.yaml with gen-hie.'
	@printf '\nmdBook defaults: MDBOOK_DIR=%s MDBOOK_HOST=%s MDBOOK_PORT=%s\n' '$(MDBOOK_DIR)' '$(MDBOOK_HOST)' '$(MDBOOK_PORT)'
	@printf 'Dashboard defaults: DASHBOARD_DIR=%s DASHBOARD_HOST=%s DASHBOARD_API_TARGET=%s DASHBOARD_API_ROOT=%s DASHBOARD_API_BASE=%s DASHBOARD_API_TIMEOUT_MS=%s\n' '$(DASHBOARD_DIR)' '$(DASHBOARD_HOST)' '$(DASHBOARD_API_TARGET)' '$(DASHBOARD_API_ROOT)' '$(DASHBOARD_API_BASE)' '$(DASHBOARD_API_TIMEOUT_MS)'
	@printf 'TaskSchedule defaults: TASKSCHEDULE_BROKER_CONFIG=%s TASKSCHEDULE_WORKER_CONFIG=%s TASKSCHEDULE_CLIENT_CONFIG=%s TASKSCHEDULE_TASK_TOML=%s TASKSCHEDULE_TASK_TEMPLATE_OUT=%s\n' '$(TASKSCHEDULE_BROKER_CONFIG)' '$(TASKSCHEDULE_WORKER_CONFIG)' '$(TASKSCHEDULE_CLIENT_CONFIG)' '$(TASKSCHEDULE_TASK_TOML)' '$(TASKSCHEDULE_TASK_TEMPLATE_OUT)'

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
	@for target in $(CI_TEST_TARGETS); do \
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
	VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run build

dashboard-dev:
	DASHBOARD_HOST="$(DASHBOARD_HOST)" DASHBOARD_API_TARGET="$(DASHBOARD_API_TARGET)" VITE_TASKSCHEDULE_API_TARGET="$(DASHBOARD_API_TARGET)" VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run dev

dashboard-preview:
	VITE_TASKSCHEDULE_API_BASE="$(DASHBOARD_API_BASE)" VITE_TASKSCHEDULE_API_ROOT="$(DASHBOARD_API_ROOT)" VITE_TASKSCHEDULE_API_TIMEOUT_MS="$(DASHBOARD_API_TIMEOUT_MS)" npm --prefix $(DASHBOARD_DIR) run preview

task-schedule-build-server:
	cabal build TaskSchedule:exe:ts-server

task-schedule-build-worker:
	cabal build TaskSchedule:exe:ts-worker

task-schedule-build-client:
	cabal build TaskSchedule:exe:ts-client

task-schedule-build-all: task-schedule-build-server task-schedule-build-worker task-schedule-build-client

task-schedule-server:
	cabal run TaskSchedule:exe:ts-server -- $(TASKSCHEDULE_BROKER_CONFIG)

task-schedule-broker: task-schedule-server

task-schedule-worker:
	cabal run TaskSchedule:exe:ts-worker -- $(TASKSCHEDULE_WORKER_CONFIG)

task-schedule-submit:
	cabal run TaskSchedule:exe:ts-client -- $(TASKSCHEDULE_CLIENT_CONFIG) $(TASKSCHEDULE_TASK_TOML)

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

hie:
	gen-hie > hie.yaml
