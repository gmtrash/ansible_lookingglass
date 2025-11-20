#!/bin/bash
#############################################################################
##                    VFIO Common Library Functions                       ##
#############################################################################
## Reusable functions for VFIO GPU passthrough operations

# Source this file in your scripts:
# source "$(dirname "$0")/lib/vfio-common.sh"

#############################################################################
## Logging Functions
#############################################################################

log_info() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] INFO: $*" | tee -a "${VFIO_LOGFILE:-/var/log/libvirt/vfio.log}"
}

log_error() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] ERROR: $*" >&2 | tee -a "${VFIO_LOGFILE:-/var/log/libvirt/vfio.log}"
}

log_warn() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] WARN: $*" | tee -a "${VFIO_LOGFILE:-/var/log/libvirt/vfio.log}"
}

#############################################################################
## Display Manager Functions
#############################################################################

get_display_manager() {
    local dispmgr=""

    # Check for systemd-based systems
    if [[ -x /run/systemd/system ]]; then
        # Handle KDE special case
        if pgrep -l "plasma" | grep -q "plasmashell"; then
            echo "display-manager"
            return 0
        fi

        # Get display manager from systemd service
        if [[ -f /etc/systemd/system/display-manager.service ]]; then
            dispmgr=$(grep 'ExecStart=' /etc/systemd/system/display-manager.service | awk -F'/' '{print $(NF)}')
            echo "$dispmgr"
            return 0
        fi
    fi

    log_error "Could not detect display manager"
    return 1
}

stop_display_manager() {
    local dispmgr=$(get_display_manager)

    if [[ -z "$dispmgr" ]]; then
        log_error "No display manager found to stop"
        return 1
    fi

    log_info "Detected display manager: $dispmgr"

    if systemctl is-active --quiet "$dispmgr.service"; then
        # Store display manager name for later restoration
        echo "$dispmgr" > /tmp/vfio-store-display-manager

        log_info "Stopping $dispmgr service"
        systemctl stop "$dispmgr.service"
        systemctl isolate multi-user.target

        # Wait for display manager to fully stop
        local timeout=30
        while systemctl is-active --quiet "$dispmgr.service" && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done

        if systemctl is-active --quiet "$dispmgr.service"; then
            log_error "Display manager failed to stop within timeout"
            return 1
        fi

        log_info "Display manager stopped successfully"
        return 0
    else
        log_info "Display manager is not running"
        return 0
    fi
}

start_display_manager() {
    if [[ ! -f /tmp/vfio-store-display-manager ]]; then
        log_warn "No stored display manager found"
        return 1
    fi

    local dispmgr=$(cat /tmp/vfio-store-display-manager)
    log_info "Restarting display manager: $dispmgr"

    systemctl start "$dispmgr.service"

    if systemctl is-active --quiet "$dispmgr.service"; then
        log_info "Display manager started successfully"
        rm -f /tmp/vfio-store-display-manager
        return 0
    else
        log_error "Failed to start display manager"
        return 1
    fi
}

#############################################################################
## VT Console Functions
#############################################################################

unbind_vtconsoles() {
    log_info "Unbinding VT consoles"

    # Clean up previous console bindings
    [[ -f /tmp/vfio-bound-consoles ]] && rm -f /tmp/vfio-bound-consoles

    for ((i = 0; i < 16; i++)); do
        if [[ -e /sys/class/vtconsole/vtcon${i} ]]; then
            if grep -q "frame buffer" /sys/class/vtconsole/vtcon${i}/name 2>/dev/null; then
                echo 0 > /sys/class/vtconsole/vtcon${i}/bind
                echo "$i" >> /tmp/vfio-bound-consoles
                log_info "Unbound VT console $i"
            fi
        fi
    done
}

rebind_vtconsoles() {
    if [[ ! -f /tmp/vfio-bound-consoles ]]; then
        log_warn "No VT consoles to rebind"
        return 0
    fi

    log_info "Rebinding VT consoles"

    while read -r console_num; do
        if [[ -e /sys/class/vtconsole/vtcon${console_num} ]]; then
            if grep -q "frame buffer" /sys/class/vtconsole/vtcon${console_num}/name 2>/dev/null; then
                echo 1 > /sys/class/vtconsole/vtcon${console_num}/bind
                log_info "Rebound VT console $console_num"
            fi
        fi
    done < /tmp/vfio-bound-consoles

    rm -f /tmp/vfio-bound-consoles
}

#############################################################################
## GPU Driver Functions
#############################################################################

detect_gpu_vendor() {
    local vendor=""

    if lspci -nn | grep -e VGA | grep -q NVIDIA; then
        vendor="nvidia"
    elif lspci -nn | grep -e VGA | grep -q AMD; then
        vendor="amd"
    elif lspci -nn | grep -e VGA | grep -q Intel; then
        vendor="intel"
    fi

    echo "$vendor"
}

unload_gpu_drivers() {
    local vendor=$(detect_gpu_vendor)

    if [[ -z "$vendor" ]]; then
        log_error "Could not detect GPU vendor"
        return 1
    fi

    log_info "Detected $vendor GPU"
    echo "$vendor" > /tmp/vfio-gpu-vendor

    # Unbind EFI framebuffer if it exists
    if [[ -e /sys/bus/platform/drivers/efi-framebuffer/efi-framebuffer.0 ]]; then
        echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null
        log_info "Unbound EFI framebuffer"
    fi

    case "$vendor" in
        nvidia)
            log_info "Unloading NVIDIA drivers"
            modprobe -r nvidia_uvm 2>/dev/null
            modprobe -r nvidia_drm 2>/dev/null
            modprobe -r nvidia_modeset 2>/dev/null
            modprobe -r nvidia 2>/dev/null
            modprobe -r i2c_nvidia_gpu 2>/dev/null
            modprobe -r drm_kms_helper 2>/dev/null
            modprobe -r drm 2>/dev/null
            ;;
        amd)
            log_info "Unloading AMD drivers"
            modprobe -r amdgpu 2>/dev/null
            modprobe -r radeon 2>/dev/null
            modprobe -r drm_kms_helper 2>/dev/null
            modprobe -r drm 2>/dev/null
            ;;
        intel)
            log_info "Unloading Intel drivers"
            modprobe -r i915 2>/dev/null
            modprobe -r drm_kms_helper 2>/dev/null
            modprobe -r drm 2>/dev/null
            ;;
    esac

    log_info "$vendor GPU drivers unloaded"
}

load_gpu_drivers() {
    if [[ ! -f /tmp/vfio-gpu-vendor ]]; then
        log_error "No stored GPU vendor information"
        return 1
    fi

    local vendor=$(cat /tmp/vfio-gpu-vendor)
    log_info "Loading $vendor GPU drivers"

    case "$vendor" in
        nvidia)
            modprobe drm
            modprobe drm_kms_helper
            modprobe i2c_nvidia_gpu
            modprobe nvidia
            modprobe nvidia_modeset
            modprobe nvidia_drm
            modprobe nvidia_uvm
            ;;
        amd)
            modprobe drm
            modprobe amdgpu
            modprobe radeon
            modprobe drm_kms_helper
            ;;
        intel)
            modprobe drm
            modprobe drm_kms_helper
            modprobe i915
            ;;
    esac

    log_info "$vendor GPU drivers loaded"
    rm -f /tmp/vfio-gpu-vendor
}

load_vfio_drivers() {
    log_info "Loading VFIO drivers"
    modprobe vfio
    modprobe vfio_pci
    modprobe vfio_iommu_type1
    log_info "VFIO drivers loaded"
}

unload_vfio_drivers() {
    log_info "Unloading VFIO drivers"
    modprobe -r vfio_pci
    modprobe -r vfio_iommu_type1
    modprobe -r vfio
    log_info "VFIO drivers unloaded"
}

#############################################################################
## CPU Management Functions
#############################################################################

pin_host_cpus() {
    local cpu_list="$1"

    if [[ -z "$cpu_list" ]]; then
        log_error "No CPU list provided for pinning"
        return 1
    fi

    log_info "Pinning host processes to CPUs: $cpu_list"

    systemctl set-property --runtime -- system.slice AllowedCPUs="$cpu_list"
    systemctl set-property --runtime -- user.slice AllowedCPUs="$cpu_list"
    systemctl set-property --runtime -- init.scope AllowedCPUs="$cpu_list"

    log_info "Host CPU pinning complete"
}

unpin_host_cpus() {
    local cpu_list="$1"

    if [[ -z "$cpu_list" ]]; then
        log_error "No CPU list provided for unpinning"
        return 1
    fi

    log_info "Unpinning host processes to CPUs: $cpu_list"

    systemctl set-property --runtime -- system.slice AllowedCPUs="$cpu_list"
    systemctl set-property --runtime -- user.slice AllowedCPUs="$cpu_list"
    systemctl set-property --runtime -- init.scope AllowedCPUs="$cpu_list"

    log_info "Host CPU unpinning complete"
}

#############################################################################
## Hugepage Functions
#############################################################################

allocate_hugepages() {
    local num_pages="$1"

    if [[ -z "$num_pages" ]]; then
        log_error "No hugepage count specified"
        return 1
    fi

    local current_pages=$(cat /proc/sys/vm/nr_hugepages)

    if [[ "$current_pages" -ge "$num_pages" ]]; then
        log_info "Hugepages already allocated ($current_pages >= $num_pages)"
        return 0
    fi

    log_info "Allocating $num_pages hugepages"

    # Compact memory to increase allocation success
    echo 3 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory

    echo "$num_pages" > /proc/sys/vm/nr_hugepages

    local allocated=$(cat /proc/sys/vm/nr_hugepages)

    if [[ "$allocated" -lt "$num_pages" ]]; then
        log_error "Failed to allocate requested hugepages (got $allocated, wanted $num_pages)"
        return 1
    fi

    log_info "Successfully allocated $allocated hugepages"
    return 0
}

deallocate_hugepages() {
    log_info "Deallocating hugepages"
    echo 0 > /proc/sys/vm/nr_hugepages
    log_info "Hugepages deallocated"
}

#############################################################################
## System Optimization Functions
#############################################################################

apply_performance_tweaks() {
    log_info "Applying performance optimizations"

    # Reduce VM stat polling
    sysctl -w vm.stat_interval=120

    # Disable watchdog to prevent NMI interrupts
    sysctl -w kernel.watchdog=0

    # Allow RT processes more CPU time
    echo -1 > /proc/sys/kernel/sched_rt_runtime_us

    log_info "Performance optimizations applied"
}

revert_performance_tweaks() {
    log_info "Reverting performance optimizations"

    sysctl -w vm.stat_interval=1
    sysctl -w kernel.watchdog=1
    echo 950000 > /proc/sys/kernel/sched_rt_runtime_us

    log_info "Performance optimizations reverted"
}

#############################################################################
## Validation Functions
#############################################################################

check_iommu_enabled() {
    if ! dmesg | grep -qi "iommu.*enabled"; then
        log_error "IOMMU not enabled in kernel"
        return 1
    fi
    log_info "IOMMU is enabled"
    return 0
}

check_vfio_modules() {
    if ! lsmod | grep -q vfio; then
        log_error "VFIO modules not loaded"
        return 1
    fi
    log_info "VFIO modules are loaded"
    return 0
}
