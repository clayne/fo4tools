all:

prereq: parallel

/usr/local/bin/parallel:
	tempdir=$$(mktemp -d); \
	curl -s 'ftp://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2' | tar -C "$$tempdir" -xpjvf -; \
	cd "$$tempdir"/parallel-* && ./configure --prefix=/usr/local && make && make install; \
	rm -rf "$$tempdir" \
	\
	# avoid needing to invoke parallel with --will-cite,
	# see e.g see https://bugs.launchpad.net/ubuntu/+source/parallel/+bug/1779764
	mkdir -p "$$HOME/.parallel" && touch "$$HOME/.parallel/will-cite"

.PHONY parallel: /usr/local/bin/parallel

install: prereq all
	cp -Rp bin/* /usr/local/bin
	cp -Rp etc/* /usr/local/etc
