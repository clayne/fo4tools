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

test:
	prove -rbl -j8 t

test-regen:
	TEST_REGEN=1 prove -rbl -j8 t

cov:
	cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover='+ignore_re,^(t/|/)' prove -rbl -j8 t
	cover

.PHONY: tags
tags:
	ctags -f tags --recurse --totals \
		--exclude=blib \
		--exclude=.git \
		--exclude='*~' \
		--exclude='nytprof' \
		--exclude='cover_db' \
		--languages=C,Perl --langmap=Perl:+.t \
