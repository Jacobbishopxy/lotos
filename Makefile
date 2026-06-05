# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

.DEFAULT_GOAL := help

MDBOOK_DIR ?= docs/book/lotos
MDBOOK_HOST ?= 0.0.0.0
MDBOOK_PORT ?= 3004
DASHBOARD_DIR ?= applications/dashboard

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

.PHONY: help tree clean update build ci-build ci-test ci-docs ci-check book-build book-serve docs-build docs-serve dashboard-install dashboard-build dashboard-dev dashboard-preview example-minimal smoke-single smoke-multi hie

help:
	@printf '%s\n' 'Lotos Make targets:'
	@printf '  %-16s %s\n' 'help' 'Show this help (default target).'
	@printf '  %-16s %s\n' 'tree' 'Print repository tree using .gitignore rules.'
	@printf '  %-16s %s\n' 'clean' 'Run cabal clean.'
	@printf '  %-16s %s\n' 'update' 'Run cabal update.'
	@printf '  %-16s %s\n' 'build' 'Build all workspace components.'
	@printf '  %-16s %s\n' 'ci-build' 'Build all components with tests enabled.'
	@printf '  %-16s %s\n' 'ci-test' 'Run bounded regression suites in CI_TEST_TARGETS.'
	@printf '  %-16s %s\n' 'ci-docs' 'Build documentation via book-build.'
	@printf '  %-16s %s\n' 'ci-check' 'Run ci-build, ci-test, and ci-docs.'
	@printf '  %-16s %s\n' 'book-build' 'Build mdBook from MDBOOK_DIR.'
	@printf '  %-16s %s\n' 'book-serve' 'Serve mdBook on MDBOOK_HOST:MDBOOK_PORT.'
	@printf '  %-16s %s\n' 'docs-build' 'Alias for book-build.'
	@printf '  %-16s %s\n' 'docs-serve' 'Alias for book-serve.'
	@printf '  %-16s %s\n' 'dashboard-install' 'Install dashboard npm dependencies.'
	@printf '  %-16s %s\n' 'dashboard-build' 'Build the dashboard Vite app.'
	@printf '  %-16s %s\n' 'dashboard-dev' 'Run the dashboard Vite dev server.'
	@printf '  %-16s %s\n' 'dashboard-preview' 'Preview the built dashboard locally.'
	@printf '  %-16s %s\n' 'example-minimal' 'Run the bounded minimal scheduler preview.'
	@printf '  %-16s %s\n' 'smoke-single' 'Run single-worker TaskSchedule smoke.'
	@printf '  %-16s %s\n' 'smoke-multi' 'Run multi-worker/capacity TaskSchedule smoke.'
	@printf '  %-16s %s\n' 'hie' 'Regenerate hie.yaml with gen-hie.'
	@printf '\nmdBook defaults: MDBOOK_DIR=%s MDBOOK_HOST=%s MDBOOK_PORT=%s\n' '$(MDBOOK_DIR)' '$(MDBOOK_HOST)' '$(MDBOOK_PORT)'
	@printf 'Dashboard default: DASHBOARD_DIR=%s\n' '$(DASHBOARD_DIR)'

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
	npm --prefix $(DASHBOARD_DIR) run build

dashboard-dev:
	npm --prefix $(DASHBOARD_DIR) run dev

dashboard-preview:
	npm --prefix $(DASHBOARD_DIR) run preview

example-minimal:
	cabal run lotos-minimal-scheduler-example:exe:mini-scheduler-preview

smoke-single:
	scripts/task-schedule-smoke.sh

smoke-multi:
	scripts/task-schedule-multi-worker-smoke.sh

hie:
	gen-hie > hie.yaml
