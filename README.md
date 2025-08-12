# Prometheus CVMFS Exporter

A Prometheus exporter for monitoring CernVM File System (CVMFS) clients. This tool collects comprehensive metrics from CVMFS repositories and exposes them in Prometheus format for monitoring and alerting.

Other exporters for CVMFS exist - this one was written to have a lightweight package without dependencies (in particular python). If you don't mind python, you could also take a look at https://github.com/guilbaults/cvmfs-exporter. Thanks to Simon Guilbaults for inspiration of this exporter, and having reserved port 9868 for CVMFS!

## Overview

The prometheus-cvmfs-exporter provides detailed insights into CVMFS client performance, cache utilization, network activity, and system resource usage. It supports both standalone execution and systemd service deployment with socket activation.

### Features

- **Comprehensive Metrics**: Collects 20+ different CVMFS metrics per repository
- **Multi-Repository Support**: Automatically discovers and monitors all mounted CVMFS repositories

## Installation

### Package Installation

**RPM-based systems (RHEL, CentOS, AlmaLinux, Fedora):**
```bash
sudo rpm -ivh prometheus-cvmfs-exporter-1.0.0-1.el9.noarch.rpm
sudo systemctl enable --now cvmfs-client-prometheus.socket
```

**DEB-based systems (Debian, Ubuntu):**
```bash
sudo dpkg -i prometheus-cvmfs-exporter_1.0.0-1_all.deb
sudo systemctl enable --now cvmfs-client-prometheus.socket
```

### Manual Installation

```bash
# Install script and systemd files
make install install-systemd

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable --now cvmfs-client-prometheus.socket
```

## Usage

### Command Line Options

```bash
/usr/libexec/cvmfs/cvmfs-prometheus.sh [OPTIONS]

Options:
  -h, --help                    Show help message
  --http                        Add HTTP protocol header to output
  --non-standard-mountpoints    Use cvmfs_config status instead of findmnt
                               for repository discovery
```

### Usage Examples

**Direct execution (one-time metrics collection):**
```bash
/usr/libexec/cvmfs/cvmfs-prometheus.sh
```

**HTTP server mode (for web scraping):**
```bash
/usr/libexec/cvmfs/cvmfs-prometheus.sh --http
```

**Non-standard mountpoints:**
```bash
/usr/libexec/cvmfs/cvmfs-prometheus.sh --non-standard-mountpoints
```

### Systemd Service

The exporter runs as a systemd socket-activated service:

```bash
# Check service status
sudo systemctl status cvmfs-client-prometheus.socket

# View service logs
sudo journalctl -u cvmfs-client-prometheus@.service

# Test metrics endpoint
curl http://localhost:9868
```

## Metrics Summary

The exporter collects the following categories of metrics:

### Cache Metrics
- `cvmfs_cached_bytes` - Currently cached data size
- `cvmfs_pinned_bytes` - Pinned cache data size
- `cvmfs_total_cache_size_bytes` - Configured cache limit
- `cvmfs_physical_cache_size_bytes` - Physical cache volume size
- `cvmfs_physical_cache_avail_bytes` - Available cache space
- `cvmfs_hitrate` - Cache hit rate percentage
- `cvmfs_ncleanup24` - Cache cleanups in last 24 hours

### Network & Download Metrics
- `cvmfs_rx_total` - Total bytes downloaded since mount
- `cvmfs_ndownload_total` - Total files downloaded since mount
- `cvmfs_speed` - Average download speed
- `cvmfs_proxy` - Available proxy servers
- `cvmfs_active_proxy` - Currently active proxy
- `cvmfs_timeout` - Proxy connection timeout
- `cvmfs_timeout_direct` - Direct connection timeout

### Repository Status Metrics
- `cvmfs_repo` - Repository version and revision information
- `cvmfs_uptime_seconds` - Time since repository mount
- `cvmfs_mount_epoch_timestamp` - Repository mount timestamp
- `cvmfs_repo_expires_seconds` - Root catalog expiration time

### System Resource Metrics
- `cvmfs_cpu_user_total` - CPU time in userspace
- `cvmfs_cpu_system_total` - CPU time in kernel space
- `cvmfs_maxfd` - Maximum file descriptors available
- `cvmfs_usedfd` - Currently used file descriptors
- `cvmfs_ndiropen` - Number of open directories
- `cvmfs_pid` - CVMFS process ID

### Error & Monitoring Metrics
- `cvmfs_nioerr_total` - Total I/O errors encountered
- `cvmfs_timestamp_last_ioerr` - Timestamp of last I/O error
- `cvmfs_nclg` - Number of loaded nested catalogs
- `cvmfs_inode_max` - Highest possible inode number

## Configuration

### Repository Discovery

By default, the exporter uses `findmnt` to discover CVMFS repositories mounted under `/cvmfs`. For non-standard setups, use the `--non-standard-mountpoints` flag to use `cvmfs_config status` instead.

### Systemd Configuration

The systemd service includes security hardening and resource limits:
- Runs as `cvmfs` user/group
- Restricted system call access
- Memory limit: 32MB
- CPU weight: 30 (low priority)
- I/O scheduling: best-effort, priority 7

### Prometheus Configuration

Add the following to your Prometheus configuration:

```yaml
scrape_configs:
  - job_name: 'cvmfs-exporter'
    static_configs:
      - targets: ['localhost:9868']
    scrape_interval: 30s
    scrape_timeout: 10s
```

## Requirements

- **CVMFS**: CernVM File System client installed and configured
- **System Tools**: `attr`, `bc`, `findmnt`, `grep`, `cut`, `tr`
- **Permissions**: Read access to CVMFS cache files and extended attributes
- **Network**: Port 9868 for HTTP metrics endpoint (when using systemd socket)

## Building from Source

```bash
# Build packages
make package          # Build both RPM and DEB
make rpm             # Build RPM only
make deb             # Build DEB only (requires Debian/Ubuntu)

# Install from source
make install install-systemd
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the user has read access to CVMFS cache files
2. **No Metrics**: Verify CVMFS repositories are mounted and accessible
3. **Socket Connection Failed**: Check if systemd socket is active and port 9868 is available

### Debug Commands

```bash
# Test script manually
/usr/libexec/cvmfs/cvmfs-prometheus.sh --help

# Check CVMFS status
cvmfs_config status

# Verify repository mounts
findmnt -t fuse.cvmfs

# Check systemd service
systemctl status cvmfs-client-prometheus.socket
journalctl -u cvmfs-client-prometheus@.service
```

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## Related Projects

- [CernVM-FS](https://github.com/cvmfs/cvmfs) - The CernVM File System
- [Prometheus](https://prometheus.io/) - Monitoring and alerting toolkit
