# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

MDBOOK_DIR ?= docs/book/lotos
MDBOOK_HOST ?= 0.0.0.0
MDBOOK_PORT ?= 3004

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

.PHONY: tree clean update build ci-build ci-test ci-docs ci-check book-build book-serve docs-build docs-serve smoke-single smoke-multi hie

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

smoke-single:
	scripts/task-schedule-smoke.sh

smoke-multi:
	scripts/task-schedule-multi-worker-smoke.sh

hie:
	gen-hie > hie.yaml
