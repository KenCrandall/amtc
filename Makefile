
# Makefile - part of amtc
# https://github.com/schnoddelbotz/amtc
#
# Toplevel Makefile for amtc and amtc-web(2).
#
# Targets:
# make amtc      -- build amtc C binary
# make amtc-web  -- build amtc-web application (V2 ... incomplete yet)
# make package   -- build a deb/rpm/osx package of amtc & amtc-web
# make install-package -- build and install package for current platform (sudo!)
# make purge     -- remove any installed package, INCLUDING data (sudo!)
#
# make dist      -- prepare dist/ tree for distribution
# make install   -- install amtc and amtc-web, respects $DESTDIR
# make deb       -- build debian/raspian package of amtc incl. amtc-web
# make rpm       -- build RPMs (RHEL/CentOS/Fedora...) of amtc and amtc-web
# make osxpkg    -- build OSX installer .pkg
# make clean     -- remove build artifacts
# make debclean  -- remove .deb package build artifacts, including .deb built
# make farmbuild -- build release packages on VM build hosts

AMTCV = $(shell cat version)
APP   = amtc-$(AMTCV)
SHELL = bash

RPMBUILD  ?= $(HOME)/rpmbuild
RPMSRC    ?= "$(RPMBUILD)/SOURCES/amtc-$(AMTCV).tar.gz"
DESTDIR   ?= /
BINDIR    ?= usr/bin
WWWDIR    ?= usr/share/amtc-web
ETCDIR    ?= etc
DATADIR   ?= var/lib
AMTCWEBDIR = amtc-web2

# for farmbuild target - build hosts
HOSTS_deb  = debian7 ubuntu14 raspbian7
HOSTS_rpm  = fedora20 centos7

# note: debian derivates (ubuntu, raspbian...) have /etc/d_v, too.
PKGTYPE = $(shell (test -f /etc/debian_version && echo deb) || \
		  (test -f /etc/redhat-release && echo rpm) || echo osxpkg)

APACHECONFD = $(shell test -d /etc/apache2/conf-enabled && \
		      echo conf-enabled || echo conf.d)

#
all: amtc amtc-web

# build amtc C binary
amtc:
	cd src && make

# build amtc-web (fetch/concat js & css libs)
amtc-web:
	cd $(AMTCWEBDIR) && make -j10

clean:
	rm -rf dist amtc amtc*.{deb,pkg} *.build debian/amtc \
        	osxpkgscripts osxpkgroot Distribution.xml
	cd src && make clean
	cd $(AMTCWEBDIR) && make clean

install: dist
	mkdir -p $(DESTDIR)
	cp -R dist/* $(DESTDIR)
	rm -f $(DESTDIR)/$(WWWDIR)/.htaccess $(DESTDIR)/$(WWWDIR)/basic-auth/.htaccess
	mkdir -p $(DESTDIR)/etc/apache2/$(APACHECONFD)
	cp $(AMTCWEBDIR)/_httpd_conf_example $(DESTDIR)/etc/amtc-web/amtc-web_httpd.conf
	ln -s ../../amtc-web/amtc-web_httpd.conf $(DESTDIR)/etc/apache2/$(APACHECONFD)

dist: amtc amtc-web
	echo "Preparing clean distribution in dist/"
	rm -rf dist
	mkdir -p dist/$(BINDIR) dist/$(WWWDIR) dist/$(ETCDIR)/cron.d dist/$(DATADIR)
	cp src/amtc dist/$(BINDIR)
	cp -R $(AMTCWEBDIR)/* dist/$(WWWDIR)
	cd dist/$(WWWDIR) && make distclean && mv _htaccess_example .htaccess && \
	   rm -f basic-auth/_htaccess.default config/_htpasswd.default data/amtc-web.db \
	   config/siteconfig.php build.sh Makefile Makefile.Sources
	cd dist && mv $(WWWDIR)/crontab-example.txt $(ETCDIR)/cron.d/amtc-web
	cd dist && mv $(WWWDIR)/config $(ETCDIR)/amtc-web && mv $(WWWDIR)/data $(DATADIR)/amtc-web
	cd dist/$(WWWDIR) && ln -s /$(ETCDIR)/amtc-web config && ln -s /$(DATADIR)/amtc-web data
	cd dist/$(WWWDIR) && perl -pi -e "s@AuthUserFile .*@AuthUserFile /$(ETCDIR)/amtc-web/.htpasswd@" basic-auth/.htaccess


# build package, depending on current os
package:
	make $(PKGTYPE)

# build q+d debian .deb package (into ../)
deb: clean
	echo y | dh_make --createorig -s -p amtc_$(AMTCV) || true
	echo  -e "#!/bin/sh -e\nchown www-data:www-data /var/lib/amtc-web /etc/amtc-web\na2enmod headers\na2enmod rewrite\nservice apache2 restart" > debian/postinst
	perl -pi -e 's@Description: .*@Description: Intel AMT/DASH remote power management tool@' debian/control
	perl -pi -e 's@^Depends: (.*)@Depends: $$1, apache2|lighttpd|nginx, php5-curl, php5-sqlite|php5-mysql|php5-pgsql@' debian/control
	perl -pi -e 's@^Build-Depends: (.*)@Build-Depends: $$1, curl, vim-common, libcurl3, libcurl4-gnutls-dev, libgnutls-dev@' debian/control
	debuild -i -us -uc -b

# remove debian/ subdirectory and trash package(s) built
debclean: clean
	rm -rf debian ../amtc_*

# build RPM package (into ~/rpmbuild/RPMS/)
rpm: clean
	mkdir -p $(RPMBUILD)/SOURCES
	cd ..; mv amtc $(APP); tar --exclude-vcs -czf $(RPMSRC) $(APP); mv $(APP) amtc
	rpmbuild -ba amtc.spec

# apply RHELoid + apache 2.4 changes (if installed _on buildhost_)
# called by amtc.spec%install
rpmfixup:
	mv $(DESTDIR)/etc/apache2 $(DESTDIR)/etc/httpd
	rpm -qa | grep httpd-2.4 && perl -pi -e 'BEGIN{undef $$/;} s@Order allow,deny\n\s+Allow from all@Require all granted@sm' $(DESTDIR)/etc/amtc-web/amtc-web_httpd.conf || true
	rpm -qa | grep httpd-2.4 && perl -pi -e 'BEGIN{undef $$/;} s@Order allow,deny\n\s+Deny from all@Require all denied@smg' $(DESTDIR)/etc/amtc-web/amtc-web_httpd.conf || true

# build OSX .pkg (into ./); use SecureTransport;
# postinst enables system apache's php5 module
osxpkg: clean
	mkdir -p osxpkgscripts osxpkgroot
	DESTDIR=osxpkgroot make install
	cp osxpkgresources/postinstall osxpkgscripts
	chmod +x osxpkgscripts/postinstall
	mv osxpkgroot/etc/apache2/conf.d osxpkgroot/etc/apache2/other
	pkgbuild --root osxpkgroot --scripts osxpkgscripts \
		 --identifier ch.hacker.amtc --version $(AMTCV) amtc.pkg
	productbuild --synthesize --package amtc.pkg Distribution.xml
	perl -pi -e 's@</installer-gui-script>@ \
		<title>amtc</title> \
		<welcome file="welcome.rtf" mime-type="text/rtf" /> \
		<conclusion file="conclusion.rtf" mime-type="text/rtf" /> \
		<background file="amtc-installer-bg.png" mime-type="image/png" alignment="bottomleft" scaling="none" /> \
		</installer-gui-script>@' Distribution.xml
	productbuild --distribution Distribution.xml --resources osxpkgresources amtc_$(AMTCV)-unsigned.pkg
	-productsign --sign 'Developer ID Installer' amtc_$(AMTCV)-unsigned.pkg amtc_$(AMTCV)-OSX_$(shell sw_vers -productVersion|cut -d. -f1-2).pkg

# build and install package for current platform. requires sudo privileges.
install-package: package
	test "$(PKGTYPE)" = "osxpkg" && sudo installer -tgt / -pkg amtc_$(AMTCV)-OSX_$(shell sw_vers -productVersion|cut -d. -f1-2).pkg || true
	test "$(PKGTYPE)" = "deb"    && (sudo dpkg -i ../amtc_*.deb ; sudo apt-get install -f) || true
	test "$(PKGTYPE)" = "rpm"    && sudo yum localinstall $(RPMBUILD)/RPMS/*/*.rpm || true
	@echo
	@echo "Done! If no errors occured, try visiting http://localhost/amtc-web/ now."
	@echo "After completing installation, change the default admin password ('amtc')!"

# uninstall any installed package and remove ANY file/directory created by amtc-web
purge:
ifeq ($(PKGTYPE),osxpkg)
	-sudo pkgutil --forget ch.hacker.amtc
else ifeq ($(PKGTYPE),deb)
	-sudo apt-get purge -y amtc
else ifeq ($(PKGTYPE),rpm)
	-sudo yum remove -y amtc amtc-web amtc-debuginfo
endif
	sudo rm -rf /etc/amtc-web /var/lib/amtc-web /usr/share/amtc-web /etc/{httpd,apache2}/{other,conf.d}/amtc-web_httpd.conf


# build farm / 'internal' use only: build and fetch releases on/from remote VMs
farmbuild:
	test `uname -s` = 'Darwin' || exit 1
	mkdir -p releases/$(AMTCV)
	make osxpkg
	cp amtc_$(AMTCV)*.pkg releases/$(AMTCV)
	for host in $(HOSTS_rpm) $(HOSTS_deb); do ssh $$host 'cd checkouts/amtc; git pull; make debclean package'; done
	for host in $(HOSTS_rpm); do scp $$host:rpmbuild/RPMS/*/*.rpm releases/$(AMTCV); done
	for host in $(HOSTS_deb); do file=`ssh $$host "cd checkouts; ls -1 amtc_*.deb"`; scp $$host:checkouts/$$file releases/$(AMTCV)/$${host}_$${file}; done


#
.PHONY:	amtc-web
