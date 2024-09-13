# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

include Makefile.env

build-all:
	cabal build all

install-cron-search:
	cd lotos && cabal install lotos:exe:cron-search -j \
		--overwrite-policy=always \
		--install-method=copy \
		--installdir=./app

hie-lotos:
	cd lotos && gen-hie > hie.yaml

hie: hie-lotos
