# Makefile for prometheus-cvmfs-exporter
# Package for monitoring CVMFS clients with Prometheus

# Package information
PACKAGE_NAME = prometheus-cvmfs-exporter
VERSION = 1.0.0
RELEASE = 1

# Installation paths
PREFIX = /usr
BINDIR = $(PREFIX)/bin
LIBEXECDIR = $(PREFIX)/libexec/cvmfs
SYSTEMDDIR = /usr/lib/systemd/system
DOCDIR = $(PREFIX)/share/doc/$(PACKAGE_NAME)

# Source files
SCRIPT_SRC = cvmfs-client-prometheus.sh
SYSTEMD_SERVICE = systemd/cvmfs-client-prometheus@.service
SYSTEMD_SOCKET = systemd/cvmfs-client-prometheus.socket
LICENSE_FILE = LICENSE

# Build directory for packaging
BUILDDIR = build
RPMDIR = $(BUILDDIR)/rpm
DEBDIR = $(BUILDDIR)/deb

# RPM build directories
RPMBUILD_DIRS = BUILD BUILDROOT RPMS SOURCES SPECS SRPMS

.PHONY: all install uninstall package rpm deb clean help

all: help

help:
	@echo "Available targets:"
	@echo "  install          - Install the script to $(LIBEXECDIR), and systemd files"
	@echo "  uninstall        - Remove installed files"
	@echo "  package          - Build both RPM and DEB packages"
	@echo "  rpm              - Build RPM package"
	@echo "  deb              - Build DEB package"
	@echo "  clean            - Remove build artifacts"
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  LIBEXECDIR=$(LIBEXECDIR)"
	@echo "  SYSTEMDDIR=$(SYSTEMDDIR)"

install:
	@echo "Installing $(SCRIPT_SRC) to $(DESTDIR)$(LIBEXECDIR)/"
	install -d $(DESTDIR)$(LIBEXECDIR)
	install -m 755 $(SCRIPT_SRC) $(DESTDIR)$(LIBEXECDIR)/cvmfs-prometheus.sh
	@echo "Installing documentation to $(DESTDIR)$(DOCDIR)/"
	install -d $(DESTDIR)$(DOCDIR)
	install -m 644 $(LICENSE_FILE) $(DESTDIR)$(DOCDIR)/
install-systemd:
	@echo "Installing systemd files to $(DESTDIR)$(SYSTEMDDIR)/"
	install -d $(DESTDIR)$(SYSTEMDDIR)
	install -m 644 $(SYSTEMD_SERVICE) $(DESTDIR)$(SYSTEMDDIR)/
	install -m 644 $(SYSTEMD_SOCKET) $(DESTDIR)$(SYSTEMDDIR)/

uninstall:
	@echo "Removing installed files..."
	rm -f $(DESTDIR)$(LIBEXECDIR)/cvmfs-prometheus.sh
	rm -f $(DESTDIR)$(SYSTEMDDIR)/cvmfs-client-prometheus@.service
	rm -f $(DESTDIR)$(SYSTEMDDIR)/cvmfs-client-prometheus.socket
	rm -rf $(DESTDIR)$(DOCDIR)
	@echo "Uninstall complete"

# Package building targets
package: rpm deb deb-source

rpm: $(BUILDDIR)/RPMS/noarch/$(PACKAGE_NAME)-$(VERSION)-$(RELEASE).noarch.rpm

$(BUILDDIR)/RPMS/noarch/$(PACKAGE_NAME)-$(VERSION)-$(RELEASE).noarch.rpm: $(PACKAGE_NAME).spec $(SCRIPT_SRC) $(SYSTEMD_SERVICE) $(SYSTEMD_SOCKET)
	@echo "Building RPM package..."
	mkdir -p $(RPMDIR)/BUILD $(RPMDIR)/BUILDROOT $(RPMDIR)/RPMS $(RPMDIR)/SOURCES $(RPMDIR)/SPECS $(RPMDIR)/SRPMS
	cp $(PACKAGE_NAME).spec $(RPMDIR)/SPECS/
	tar -czf $(RPMDIR)/SOURCES/$(PACKAGE_NAME)-$(VERSION).tar.gz \
		--transform 's,^,$(PACKAGE_NAME)-$(VERSION)/,' \
		$(SCRIPT_SRC) $(SYSTEMD_SERVICE) $(SYSTEMD_SOCKET) $(LICENSE_FILE) Makefile
	rpmbuild --define "_topdir $(PWD)/$(RPMDIR)" \
		--define "version $(VERSION)" \
		--define "release $(RELEASE)" \
		-ba $(RPMDIR)/SPECS/$(PACKAGE_NAME).spec

deb: $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE)_all.deb

$(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE)_all.deb: debian/control debian/rules debian/install debian/changelog
	@echo "Building DEB package..."
	mkdir -p $(DEBDIR)
	cp -r debian $(DEBDIR)/
	cp -r systemd $(DEBDIR)/
	cp $(SCRIPT_SRC) $(LICENSE_FILE) Makefile $(DEBDIR)/
	cd $(DEBDIR) && dpkg-buildpackage -us -uc
	if [ -f $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE)_all.deb ]; then \
		echo "DEB package already in correct location"; \
	else \
		mv $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE)_all.deb $(BUILDDIR)/; \
	fi

# Add separate target for source package
deb-source: $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE).dsc

$(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE).dsc: debian/control debian/rules debian/install debian/changelog
	@echo "Building DEB source package..."
	mkdir -p $(DEBDIR)
	cp -r debian $(DEBDIR)/
	cp -r systemd $(DEBDIR)/
	cp $(SCRIPT_SRC) $(LICENSE_FILE) Makefile $(DEBDIR)/
	cd $(DEBDIR) && dpkg-buildpackage -us -uc -S
	mv $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE).dsc $(BUILDDIR)/
	mv $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE).tar.xz $(BUILDDIR)/
	mv $(BUILDDIR)/$(PACKAGE_NAME)_$(VERSION)-$(RELEASE)_source.changes $(BUILDDIR)/

clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILDDIR)
	@echo "Clean complete"

# Development targets
check-deps:
	@echo "Checking for required build dependencies..."
	@which rpmbuild >/dev/null 2>&1 || echo "WARNING: rpmbuild not found (needed for RPM packaging)"
	@which dpkg-buildpackage >/dev/null 2>&1 || echo "WARNING: dpkg-buildpackage not found (needed for DEB packaging)"
	@which systemctl >/dev/null 2>&1 || echo "WARNING: systemctl not found (systemd not available)"
