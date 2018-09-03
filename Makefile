setup:
	curl -s 'ftp://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2' | tar -C /tmp -xpjf -
all:
install:
	cp -Rp bin/* /usr/local/bin
	cp -Rp etc/* /usr/local/etc
