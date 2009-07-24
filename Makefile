all: install

install:
	install -d $(DESTDIR)/sbin
	install -d $(DESTDIR)/usr/share/aif/docs
	install -d $(DESTDIR)/usr/share/aif/examples
	install -d $(DESTDIR)/usr/share/aif/tests
	install -d $(DESTDIR)/usr/lib/aif/core
	install -d $(DESTDIR)/usr/lib/aif/user
	install -D -m755 src/aif.sh $(DESTDIR)/sbin/aif
	install -D -m755 src/aif-test.sh $(DESTDIR)/sbin/aif-test
	install -D -m644 README $(DESTDIR)/usr/share/aif/docs
	cp -rp src/core $(DESTDIR)/usr/lib/aif
	chmod -R 755 $(DESTDIR)/usr/lib/aif/core
	cp -rp src/user $(DESTDIR)/usr/lib/aif
	chmod -R 755 $(DESTDIR)/usr/lib/aif/user
	cp -rp examples $(DESTDIR)/usr/share/aif
	chmod -R 755 $(DESTDIR)/usr/share/aif/examples
	cp -rp tests $(DESTDIR)/usr/share/aif
	chmod -R 755 $(DESTDIR)/usr/share/aif/tests


uninstall:
	rm -f  $(DESTDIR)/sbin/aif
	rm -rf $(DESTDIR)/usr/share/aif
	rm -rf $(DESTDIR)/usr/lib/aif
