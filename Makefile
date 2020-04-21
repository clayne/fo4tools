all:

prereq: parallel

/usr/local/bin/parallel:
	tempdir=$$(mktemp -d); \
	curl -s 'ftp://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2' | tar -C "$$tempdir" -xpjvf -; \
	cd "$$tempdir"/parallel-* && ./configure --prefix=/usr/local && make && make install; \
	rm -rf "$$tempdir"

parallel: /usr/local/bin/parallel

install: prereq all
	cp -Rp bin/* /usr/local/bin
	cp -Rp etc/* /usr/local/etc
