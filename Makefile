# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

tree:
	tree . --gitignore

build-all:
	cabal build all

install-cron-search:
	cd applications && cabal install CronSearch:exe:cron-search -j \
		--overwrite-policy=always \
		--install-method=copy \
		--installdir=./app

hie:
	gen-hie > hie.yaml
