Name:           prometheus-cvmfs-exporter
Version:        %{version}
Release:        %{release}%{?dist}
Summary:        Prometheus exporter for CVMFS client monitoring

License:        BSD-3-Clause
URL:            https://github.com/cvmfs-contrib/prometheus-cvmfs
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  systemd-rpm-macros

# Runtime dependencies for the script
Requires:       bash
Requires:       attr
Requires:       bc
Requires:       cvmfs
Requires:       findutils
Requires:       grep
Requires:       coreutils
Requires:       util-linux

# Systemd dependencies
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
A Prometheus exporter for monitoring CVMFS (CernVM File System) clients.
This package provides a script that collects metrics from CVMFS repositories
and exposes them in Prometheus format, along with systemd service files
for running the exporter as a service.

The exporter collects various metrics including:
- Cache hit rates and sizes
- Download statistics
- Repository status and configuration
- Proxy usage and performance
- System resource usage by CVMFS processes

%prep
%setup -q

%build
# Nothing to build - this is a shell script package

%install
# Install using the Makefile
make install DESTDIR=%{buildroot}
make install-systemd DESTDIR=%{buildroot}
# Remove duplicate LICENSE file from doc directory since %license handles it
rm -f %{buildroot}%{_docdir}/%{name}/LICENSE

%post
%systemd_post cvmfs-client-prometheus@.service
%systemd_post cvmfs-client-prometheus.socket

%preun
%systemd_preun cvmfs-client-prometheus@.service
%systemd_preun cvmfs-client-prometheus.socket

%postun
%systemd_postun_with_restart cvmfs-client-prometheus@.service
%systemd_postun_with_restart cvmfs-client-prometheus.socket

%files
%license LICENSE
%{_libexecdir}/cvmfs/cvmfs-prometheus.sh
%{_unitdir}/cvmfs-client-prometheus@.service
%{_unitdir}/cvmfs-client-prometheus.socket

%changelog
* Mon Jan 01 2024 Package Maintainer <maintainer@example.com> - 1.0.0-1
- Initial package release
- Prometheus exporter for CVMFS client monitoring
- Includes systemd service and socket files
- Supports both legacy and modern CVMFS versions (>= 2.13.2)
- Configurable repository discovery methods
- Comprehensive metrics collection including cache, download, and proxy stats
