#!/bin/bash -u

HTTP_HEADER='FALSE'
USE_NON_STANDARD_MOUNTPOINTS='FALSE'

TMPFILE=$(mktemp)

cleanup_tmpfile() {
    if [ -n "${TMPFILE}" ] && [ -f "${TMPFILE}" ]; then
        rm -f "${TMPFILE}"
    fi
}
trap cleanup_tmpfile EXIT

# CVMFS Extended Attributes and their descriptions
declare -A CVMFS_EXTENDED_ATTRIBUTE_GAUGES=(
    ['hitrate']='CVMFS cache hit rate (%)'
    ['inode_max']='Shows the highest possible inode with the current set of loaded catalogs.'
    ['maxfd']='Shows the maximum number of file descriptors available to file system clients.'
    ['ncleanup24']='Shows the number of cache cleanups in the last 24 hours.'
    ['nclg']='Shows the number of currently loaded nested catalogs.'
    ['ndiropen']='Shows the overall number of opened directories.'
    ['pid']='Shows the process id of the CernVM-FS Fuse process.'
    ['speed']='Shows the average download speed.'
    ['useddirp']='Shows the number of file descriptors currently issued to file system clients.'
    ['usedfd']='Shows the number of open directories currently used by file system clients.'
)

#############################################################
usage() {
    echo "Usage: $0 [-h|--help] [--http] [--non-standard-mountpoints]" >&2
    echo '' >&2
    echo '  --http: add the HTTP protocol header to the output' >&2
    echo '  --non-standard-mountpoints: use cvmfs_config status instead of findmnt to discover repositories' >&2
    echo '' >&2
    echo 'NOTE: The user running this script must have read access' >&2
    echo '      to the CVMFS cache files!' >&2
    echo 'NOTE: By default, repositories are discovered using findmnt to find fuse filesystems' >&2
    echo '      mounted under /cvmfs. Use --non-standard-mountpoints for non-standard setups.' >&2
    exit 1
}

generate_metric() {
    local metric_name="$1"
    local metric_type="$2"
    local help_text="$3"
    local metric_labels="$4"
    local metric_value="$5"

    cat >>"${TMPFILE}" <<EOF
# HELP $metric_name $help_text
# TYPE $metric_name $metric_type
${metric_name}{${metric_labels}} ${metric_value}
EOF
}

convert_version_to_numeric() {
    local version="$1"
    # Convert version string like "2.13.2.0" to numeric value
    # Format: major * 10000 + minor * 100 + patch
    # Example: 2.13.2 becomes 21302
    # Ignore the build number (last field)

    # Remove any non-numeric characters except dots
    local clean_version
    clean_version=$(echo "$version" | sed 's/[^0-9.]//g')

    # Split version into components
    IFS='.' read -ra version_parts <<< "$clean_version"

    local major=${version_parts[0]:-0}
    local minor=${version_parts[1]:-0}
    local patch=${version_parts[2]:-0}
    # Ignore build number (version_parts[3])

    # Calculate numeric value: major * 10000 + minor * 100 + patch
    local numeric_version
    numeric_version=$((major * 10000 + minor * 100 + patch))

    echo "$numeric_version"
}

list_mounted_cvmfs_repos() {
    cvmfs_config status | tr -s '[:space:]' | cut -d ' ' -f 1 | sort -u
}

mountpoint_for_cvmfs_repo() {
    local reponame
    reponame="$1"

    cvmfs_talk -i "${reponame}" mountpoint
}

mountpoint_for_cvmfs_repo_standard() {
    echo "/cvmfs/${reponame}"
}

fqrn_for_cvmfs_repo() {
    local reponame
    reponame="$1"

    local repopath
    repopath=$(mountpoint_for_cvmfs_repo "${reponame}")

    attr -g fqrn "${repopath}" | tail -n +2
}

get_cvmfs_repo_extended_attribute_gauge_metrics() {
    local reponame
    reponame="$1"

    local repomountpoint
    repomountpoint=$(mountpoint_for_cvmfs_repo "${reponame}")

    local fqrn
    fqrn=$(fqrn_for_cvmfs_repo "${reponame}")

    local attribute
    for attribute in "${!CVMFS_EXTENDED_ATTRIBUTE_GAUGES[@]}"; do
        local result
        result=$(attr -g "${attribute}" "${repomountpoint}" | tail -n +2)
        generate_metric "cvmfs_${attribute}" 'gauge' "${CVMFS_EXTENDED_ATTRIBUTE_GAUGES[${attribute}]}" "repo=\"${fqrn}\"" "${result}"
    done
}

get_cvmfs_repo_proxy_metrics() {
    local reponame
    reponame="$1"

    local repomountpoint
    repomountpoint=$(mountpoint_for_cvmfs_repo "${reponame}")

    local fqrn
    fqrn=$(fqrn_for_cvmfs_repo "${reponame}")

    local proxy_list
    mapfile -t proxy_list < <(attr -g proxy_list "${repomountpoint}" | tail -n +2 | grep -v '^$')

    local proxy_filter_by_group
    mapfile -t proxy_filter_by_group < <(cvmfs_talk -i "${reponame}" proxy info | tail -n +2 | grep '^\[' | grep ']' | tr -s '[:space:]')

    local proxy
    local my_proxy_group
    for proxy in "${proxy_list[@]}"; do
        local line
        local result
        for line in "${proxy_filter_by_group[@]}"; do
            result=$(echo "${line}" | grep "${proxy}" | cut -d' ' -f 1 | tr -d '][')
            if [[ "x${result}" != 'x' ]]; then
                my_proxy_group=${result}
                break
            fi
        done
        generate_metric "cvmfs_proxy" "gauge" "Shows all registered proxies for this repository." "repo=\"${fqrn}\",group=\"${my_proxy_group}\",url=\"${proxy}\"" 1
    done
}

get_cvmfs_repo_metrics() {
    local reponame
    reponame="$1"

    local repomountpoint
    repomountpoint=$($MOUNTPOINT_FUNCTION "${reponame}")

    local fqrn
    fqrn=$(fqrn_for_cvmfs_repo "${reponame}")

    local repo_pid
    repo_pid=$(cvmfs_talk -i "${reponame}" pid)

    local cache_volume
    cache_volume=$(cvmfs_talk -i "${reponame}" parameters | grep CVMFS_CACHE_BASE | tr '=' ' ' | tr -s '[:space:]' | cut -d ' ' -f 2)

    local cached_bytes
    cached_bytes=$(cvmfs_talk -i "${reponame}" cache size | tr -d ')(' | tr -s '[:space:]' | cut -d ' ' -f 6)
    generate_metric 'cvmfs_cached_bytes' 'gauge' 'CVMFS currently cached bytes.' "repo=\"${fqrn}\"" "${cached_bytes}"

    local pinned_bytes
    pinned_bytes=$(cvmfs_talk -i "${reponame}" cache size | tr -d ')(' | tr -s '[:space:]' | cut -d ' ' -f 10)
    generate_metric 'cvmfs_pinned_bytes' 'gauge' 'CVMFS currently pinned bytes.' "repo=\"${fqrn}\"" "${pinned_bytes}"

    local total_cache_size_mb
    total_cache_size_mb=$(cvmfs_talk -i "${reponame}" parameters | grep CVMFS_QUOTA_LIMIT | tr '=' ' ' | tr -s '[:space:]' | cut -d ' ' -f 2)
    local total_cache_size
    total_cache_size=$((total_cache_size_mb * 1024 * 1024))
    generate_metric 'cvmfs_total_cache_size_bytes' 'gauge' 'CVMFS configured cache size via CVMFS_QUOTA_LIMIT.' "repo=\"${fqrn}\"" "${total_cache_size}"

    local cache_volume_max
    cache_volume_max=$(df -B1 "${cache_volume}" | tail -n 1 | tr -s '[:space:]' | cut -d ' ' -f 2)
    generate_metric 'cvmfs_physical_cache_size_bytes' 'gauge' 'CVMFS cache volume physical size.' "repo=\"${fqrn}\"" "${cache_volume_max}"

    local cache_volume_free
    cache_volume_free=$(df -B1 "${cache_volume}" | tail -n 1 | tr -s '[:space:]' | cut -d ' ' -f 4)
    generate_metric 'cvmfs_physical_cache_avail_bytes' 'gauge' 'CVMFS cache volume physical free space available.' "repo=\"${fqrn}\"" "${cache_volume_free}"

    local cvmfs_mount_version
    cvmfs_mount_version=$(attr -g version "${repomountpoint}" | tail -n +2)
    local cvmfs_mount_revision
    cvmfs_mount_revision=$(attr -g revision "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_repo' 'gauge' 'Shows the version of CVMFS used by this repository.' "repo=\"${fqrn}\",mountpoint=\"${repomountpoint}\",version=\"${cvmfs_mount_version}\",revision=\"${cvmfs_mount_revision}\"" 1

    # Generate numeric version and revision metrics
    local cvmfs_numeric_version
    cvmfs_numeric_version=$(convert_version_to_numeric "${cvmfs_mount_version}")
    generate_metric 'cvmfs_repo_version' 'gauge' 'CVMFS repository version as a numeric value for easier querying.' "repo=\"${fqrn}\"" "${cvmfs_numeric_version}"

    generate_metric 'cvmfs_repo_revision' 'gauge' 'CVMFS repository revision number.' "repo=\"${fqrn}\"" "${cvmfs_mount_revision}"

    local cvmfs_mount_rx_kb
    cvmfs_mount_rx_kb=$(attr -g rx "${repomountpoint}" | tail -n +2)
    local cvmfs_mount_rx
    cvmfs_mount_rx=$((cvmfs_mount_rx_kb * 1024))
    generate_metric 'cvmfs_rx_total' 'counter' 'Shows the overall amount of downloaded bytes since mounting.' "repo=\"${fqrn}\"" "${cvmfs_mount_rx}"

    local cvmfs_mount_uptime_minutes
    cvmfs_mount_uptime_minutes=$(attr -g uptime "${repomountpoint}" | tail -n +2)
    local now
    local rounded_now_to_minute
    local cvmfs_mount_uptime
    local cvmfs_mount_epoch_time
    now=$(date +%s)
    rounded_now_to_minute=$((now - (now % 60)))
    cvmfs_mount_uptime=$((cvmfs_mount_uptime_minutes * 60))
    cvmfs_mount_epoch_time=$((rounded_now_to_minute - cvmfs_mount_uptime))
    generate_metric 'cvmfs_uptime_seconds' 'counter' 'Shows the time since the repo was mounted.' "repo=\"${fqrn}\"" "${cvmfs_mount_uptime}"
    generate_metric 'cvmfs_mount_epoch_timestamp' 'counter' 'Shows the epoch time the repo was mounted.' "repo=\"${fqrn}\"" "${cvmfs_mount_epoch_time}"

    local cvmfs_repo_expires_min
    cvmfs_repo_expires_min=$(attr -g expires "${repomountpoint}" | tail -n +2)
    local cvmfs_repo_expires
    if case $cvmfs_repo_expires_min in never*) ;; *) false;; esac; then
      cvmfs_repo_expires="-1"
    else
      cvmfs_repo_expires=$((cvmfs_repo_expires_min * 60))
    fi
    generate_metric 'cvmfs_repo_expires_seconds' 'gauge' 'Shows the remaining life time of the mounted root file catalog in seconds. -1 if never expires.' "repo=\"${fqrn}\"" "${cvmfs_repo_expires}"

    local cvmfs_mount_ndownload
    cvmfs_mount_ndownload=$(attr -g ndownload "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_ndownload_total' 'counter' 'Shows the overall number of downloaded files since mounting.' "repo=\"${fqrn}\"" "${cvmfs_mount_ndownload}"

    local cvmfs_mount_nioerr
    cvmfs_mount_nioerr=$(attr -g nioerr "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_nioerr_total' 'counter' 'Shows the total number of I/O errors encountered since mounting.' "repo=\"${fqrn}\"" "${cvmfs_mount_nioerr}"

    local cvmfs_mount_timeout
    cvmfs_mount_timeout=$(attr -g timeout "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_timeout' 'gauge' 'Shows the timeout for proxied connections in seconds.' "repo=\"${fqrn}\"" "${cvmfs_mount_timeout}"

    local cvmfs_mount_timeout_direct
    cvmfs_mount_timeout_direct=$(attr -g timeout_direct "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_timeout_direct' 'gauge' 'Shows the timeout for direct connections in seconds.' "repo=\"${fqrn}\"" "${cvmfs_mount_timeout_direct}"

    local cvmfs_mount_timestamp_last_ioerr
    cvmfs_mount_timestamp_last_ioerr=$(attr -g timestamp_last_ioerr "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_timestamp_last_ioerr' 'counter' 'Shows the timestamp of the last ioerror.' "repo=\"${fqrn}\"" "${cvmfs_mount_timestamp_last_ioerr}"

    local cvmfs_repo_pid_statline
    cvmfs_repo_pid_statline=$(</proc/"${repo_pid}"/stat)
    local cvmfs_repo_stats
    read -ra cvmfs_repo_stats <<<"${cvmfs_repo_pid_statline}"
    local cvmfs_utime
    local cvmfs_stime
    cvmfs_utime=${cvmfs_repo_stats[13]}
    cvmfs_stime=${cvmfs_repo_stats[14]}
    local cvmfs_user_seconds
    local cvmfs_system_seconds
    cvmfs_user_seconds=$(printf "%.2f" "$(echo "scale=4; $cvmfs_utime / $CLOCK_TICK" | bc)")
    cvmfs_system_seconds=$(printf "%.2f" "$(echo "scale=4; $cvmfs_stime / $CLOCK_TICK" | bc)")
    generate_metric 'cvmfs_cpu_user_total' 'counter' 'CPU time used in userspace by CVMFS mount in seconds.' "repo=\"${fqrn}\"" "${cvmfs_user_seconds}"
    generate_metric 'cvmfs_cpu_system_total' 'counter' 'CPU time used in the kernel system calls by CVMFS mount in seconds.' "repo=\"${fqrn}\"" "${cvmfs_system_seconds}"

    # Add memory usage metric
    if [[ -f "/proc/${repo_pid}/status" ]]; then
        local memory_usage_kb
        memory_usage_kb=$(grep "VmRSS:" "/proc/${repo_pid}/status" | awk '{print $2}')
        if [[ -n "${memory_usage_kb}" ]]; then
            local memory_usage_bytes
            memory_usage_bytes=$((memory_usage_kb * 1000))
            generate_metric 'cvmfs_memory_usage_bytes' 'gauge' 'CVMFS process memory usage in bytes.' "repo=\"${fqrn}\"" "${memory_usage_bytes}"
        fi
    fi

    local cvmfs_mount_active_proxy
    cvmfs_mount_active_proxy=$(attr -g proxy "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_active_proxy' 'gauge' 'Shows the active proxy in use for this mount.' "repo=\"${fqrn}\",proxy=\"${cvmfs_mount_active_proxy}\"" 1

    # Pull in xattr based metrics with simple labels
    get_cvmfs_repo_extended_attribute_gauge_metrics "${reponame}"
    get_cvmfs_repo_proxy_metrics "${reponame}"
}

get_cvmfs_repo_metrics_new() {
    local reponame
    reponame="$1"

    local repomountpoint
    repomountpoint=$($MOUNTPOINT_FUNCTION "${reponame}")

    # Use the new "metrics prometheus" command to get most metrics
    cvmfs_talk -i "${reponame}" "metrics prometheus" >> "${TMPFILE}"

    # Still need to get maxfd via xattr since it was removed from metrics prometheus
    local maxfd_value
    maxfd_value=$(attr -g maxfd "${repomountpoint}" | tail -n +2)
    generate_metric 'cvmfs_maxfd' 'gauge' 'Shows the maximum number of file descriptors available to file system clients.' "repo=\"${reponame}\"" "${maxfd_value}"

    # Extract version and revision from the cvmfs_repo metric in TMPFILE and generate numeric metrics
    local cvmfs_repo_line
    cvmfs_repo_line=$(grep "cvmfs_repo{repo=\"${reponame}\"" "${TMPFILE}" | tail -n 1)

    if [[ -n "${cvmfs_repo_line}" ]]; then
        # Extract version from the metric line using regex
        local cvmfs_mount_version
        cvmfs_mount_version=$(echo "${cvmfs_repo_line}" | sed -n 's/.*version="\([^"]*\)".*/\1/p')

        # Extract revision from the metric line using regex
        local cvmfs_mount_revision
        cvmfs_mount_revision=$(echo "${cvmfs_repo_line}" | sed -n 's/.*revision="\([^"]*\)".*/\1/p')

        # Generate numeric version and revision metrics
        if [[ -n "${cvmfs_mount_version}" ]]; then
            local cvmfs_numeric_version
            cvmfs_numeric_version=$(convert_version_to_numeric "${cvmfs_mount_version}")
            generate_metric 'cvmfs_repo_version' 'gauge' 'CVMFS repository version as a numeric value for easier querying.' "repo=\"${reponame}\"" "${cvmfs_numeric_version}"
        fi

        if [[ -n "${cvmfs_mount_revision}" ]]; then
            generate_metric 'cvmfs_repo_revision' 'gauge' 'CVMFS repository revision number.' "repo=\"${reponame}\"" "${cvmfs_mount_revision}"
        fi
    fi

    # Extract PID from the metrics output and add memory usage metric
    local repo_pid
    repo_pid=$(grep "cvmfs_pid{repo=\"${reponame}\"}" "${TMPFILE}" | tail -n 1 | awk '{print $2}')
    if [[ -n "${repo_pid}" && -f "/proc/${repo_pid}/status" ]]; then
        local memory_usage_kb
        memory_usage_kb=$(grep "VmRSS:" "/proc/${repo_pid}/status" | awk '{print $2}')
        if [[ -n "${memory_usage_kb}" ]]; then
            local memory_usage_bytes
            memory_usage_bytes=$((memory_usage_kb * 1000))
            generate_metric 'cvmfs_memory_usage_bytes' 'gauge' 'CVMFS process memory usage in bytes.' "repo=\"${reponame}\"" "${memory_usage_bytes}"
        fi
    fi
}

get_repos_from_findmnt() {
    # Parse findmnt output to find fuse filesystems mounted under /cvmfs
    findmnt -o FSTYPE,TARGET --raw | \
    awk '$1 == "fuse" && $2 ~ /^\/cvmfs\// { gsub(/^\/cvmfs\//, "", $2); print $2 }' | \
    tr '\n' ' '
}

get_repos_from_cvmfs_config() {
    cvmfs_config status | cut -d ' ' -f 1 | tr '\n' ' '
}

check_cvmfs_version() {
    # Check if cvmfs2 version is >= 2.13.2
    local version_output
    version_output=$(cvmfs2 --version 2>/dev/null | head -n 1)
    if [ $? -ne 0 ]; then
        # cvmfs2 command not found, assume old version
        return 1
    fi

    local version
    version=$(echo "$version_output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1)
    if [ -z "$version" ]; then
        # Could not parse version, assume old version
        return 1
    fi

    # Convert version to comparable format (e.g., 2.13.2 -> 20130200)
    local major minor patch
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3)

    local version_num=$((major * 10000000 + minor * 100000 + patch * 1000))
    local min_version_num=$((2 * 10000000 + 13 * 100000 + 2 * 1000))  # 2.13.2

    [ $version_num -ge $min_version_num ]
}

#############################################################
# List "uncommon" commands we expect
for cmd in attr bc cvmfs_config cvmfs_talk grep; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

#############################################################
# setup args in the right order for making getopt evaluation
# nice and easy.  You'll need to read the manpages for more info
args=$(getopt --options 'h' --longoptions 'help,http,non-standard-mountpoints' -- "$@")
eval set -- "$args"

for arg in $@; do
    case $1 in
    --)
        # end of getopt args, shift off the -- and get out of the loop
        shift
        break 2
        ;;
    --http)
        # Add the http header to the output
        HTTP_HEADER='TRUE'
        shift
        ;;
    --non-standard-mountpoints)
        # Use cvmfs_config status to discover repositories
        USE_NON_STANDARD_MOUNTPOINTS='TRUE'
        shift
        ;;
    -h | --help)
        # get help
        shift
        usage
        ;;
    esac
done

CLOCK_TICK=$(getconf CLK_TCK)

# Determine which method to use for getting metrics
if check_cvmfs_version; then
    # CVMFS version >= 2.13.2, use new metrics prometheus command
    METRICS_FUNCTION="get_cvmfs_repo_metrics_new"
else
    # Older CVMFS version, use legacy method
    METRICS_FUNCTION="get_cvmfs_repo_metrics"
fi

# Get repository list based on selected method
if [[ "${USE_NON_STANDARD_MOUNTPOINTS}" == 'TRUE' ]]; then
    REPO_LIST=$(get_repos_from_cvmfs_config)
    MOUNTPOINT_FUNCTION="mountpoint_for_cvmfs_repo"
else
    REPO_LIST=$(get_repos_from_findmnt)
    MOUNTPOINT_FUNCTION="mountpoint_for_cvmfs_repo_standard"
fi

for REPO in $REPO_LIST; do
    $METRICS_FUNCTION "${REPO}"
done

if [[ "${HTTP_HEADER}" == 'TRUE' ]]; then
    content_length=$(stat --printf="%s" "${TMPFILE}")
    echo -ne "HTTP/1.1 200 OK\r\n"
    echo -ne "Content-Type: text/plain; version=0.0.4; charset=utf-8; escaping=underscores\r\n"
    echo -ne "Content-Length: ${content_length}\r\n"
    echo -ne "Connection: close\r\n"
    echo -ne "\r\n"
fi

cat "${TMPFILE}"
