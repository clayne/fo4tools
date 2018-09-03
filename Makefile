all:

prereq: parallel

parallel:
	rm -rf /tmp/fo4tools
	mkdir -p /tmp/fo4tools
	curl 'ftp://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2' | tar -C /tmp/fo4tools -xpjvf -
	cd /tmp/fo4tools/parallel-* && ./configure --prefix=/usr/local && make && make install

install: prereq all
	cp -Rp bin/* /usr/local/bin
	cp -Rp etc/* /usr/local/etc
