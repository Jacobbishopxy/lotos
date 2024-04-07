# author:	Jacob Xie
# date:	2024/04/07 21:14:03 Sunday
# brief:

build-all:
	cabal build all

gen-hie-lotos:
	cd lotos && gen-hie > hie.yaml

gen-hie: gen-hie-lotos
