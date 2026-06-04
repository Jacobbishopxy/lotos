# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

MDBOOK_DIR ?= docs/book/lotos
MDBOOK_HOST ?= 127.0.0.1
MDBOOK_PORT ?= 3003

tree:
	tree . --gitignore

clean:
	cabal clean

update:
	cabal update

build:
	cabal build all

book-build:
	mdbook build $(MDBOOK_DIR)

book-serve:
	mdbook serve $(MDBOOK_DIR) --hostname $(MDBOOK_HOST) --port $(MDBOOK_PORT)

docs-build: book-build

docs-serve: book-serve

hie:
	gen-hie > hie.yaml
