#!/bin/bash

# ChromeOS Unenrollment Script
# Description: This script removes a ChromeOS device from enterprise enrollment
# Note: This requires developer mode to be enabled on the ChromeOS device

# Configuration variables
LOG_FILE="/var/log/chromeos_unenrollment.log"
BACKUP_DIR="/var/backups/chromeos_unenrollment"

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to display usage information
show_usage() {
    echo "ChromeOS Unenrollment Script"
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -f, --force          Force unenrollment without confirmation"
    echo "  -b, --backup         Create backup before unenrollment"
    echo "  -r, --restore FILE   Restore from backup file"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Note: This script requires ChromeOS developer mode to be enabled."
    echo "      To enable developer mode: 1) Turn off ChromeOS 2) Press ESC + REFRESH + POWER"
    echo "      3) At the recovery screen, press CTRL+D 4) Confirm by pressing ENTER"
}

# Function to check if running in ChromeOS
check_chromeos() {
    if [ ! -f /etc/lsb-release ] || ! grep -q "CHROMEOS" /etc/lsb-release; then
        log "Error: This script is designed to run on ChromeOS only."
        echo "Error: This script is designed to run on ChromeOS only."
        exit 1
    fi
}

# Function to check if in developer mode
check_developer_mode() {
    if [ ! -d /usr/local ]; then
        log "Error: ChromeOS is not in developer mode."
        echo "Error: ChromeOS is not in developer mode."
        echo "Please enable developer mode before running this script."
        exit 1
    fi
}

# Function to create backup
create_backup() {
    local backup_file="$BACKUP_DIR/backup-$(date +%Y-%m-%d-%H%M%S).tar.gz"
    log "Creating backup at $backup_file"
    
    # Add important files to backup
    tar -czf "$backup_file" \
        /etc/lsb-release \
        /etc/chrome_dev.conf \
        /home/chronos/Local\ State \
        /home/chronos/Preferences \
        /var/lib/whitelist \
        /home/.shadow \
        /mnt/stateful_partition/etc/ \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "Backup created successfully: $backup_file"
        echo "$backup_file"
        return 0
    else
        log "Failed to create backup"
        return 1
    fi
}

# Function to restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Restoring from backup: $backup_file"
    tar -xzf "$backup_file" -C / 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "Restore completed successfully"
        return 0
    else
        log "Failed to restore from backup"
        return 1
    fi
}

# Function to perform ChromeOS unenrollment
perform_chromeos_unenrollment() {
    log "Starting ChromeOS unenrollment process"
    
    # Stop Chrome services
    log "Stopping Chrome services"
    stop ui 2>/dev/null
    stop powerd 2>/dev/null
    stop shill 2>/dev/null
    
    # Remove enrollment policies
    log "Removing enrollment policies"
    rm -rf /var/lib/whitelist/*
    rm -rf /home/chronos/Local\ State/Managed*
    rm -rf /home/chronos/Preferences/Managed*
    
    # Clear device enrollment data
    log "Clearing device enrollment data"
    rm -f /var/lib/devicesettings/policy.*
    rm -f /var/lib/devicesettings/owner.key
    
    # Remove enterprise enrollment flags
    log "Removing enterprise enrollment flags"
    if [ -f /etc/chrome_dev.conf ]; then
        sed -i '/enterprise-enrollment/d' /etc/chrome_dev.conf
        sed -i '/enrollment-token/d' /etc/chrome_dev.conf
    fi
    
    # Remove enrollment token if it exists
    rm -f /var/lib/devicesettings/enrollment-token
    
    # Clear TPM if needed
    log "Clearing TPM enrollment data"
    crossystem clear_tpm_owner_request=1
    
    # Remove any policy files
    log "Removing policy files"
    find /home/chronos -name "*policy*" -type f -delete 2>/dev/null
    find /mnt/stateful_partition -name "*policy*" -type f -delete 2>/dev/null
    
    # Mark as unenrolled
    touch /var/lib/devicesettings/unenrolled
    log "ChromeOS unenrollment completed successfully"
    
    # Restart services
    log "Restarting Chrome services"
    start shill 2>/dev/null
    start powerd 2>/dev/null
    start ui 2>/dev/null
    
    return 0
}

# Parse command line arguments
FORCE=false
BACKUP=false
RESTORE_FILE=""

while [ "$1" != "" ]; do
    case $1 in
        -f | --force )
            FORCE=true
            ;;
        -b | --backup )
            BACKUP=true
            ;;
        -r | --restore )
            shift
            RESTORE_FILE="$1"
            ;;
        -h | --help )
            show_usage
            exit 0
            ;;
        * )
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# Main execution
if [ -n "$RESTORE_FILE" ]; then
    restore_backup "$RESTORE_FILE"
    exit $?
fi

# Check if running on ChromeOS
check_chromeos

# Check if in developer mode
check_developer_mode

# Create backup if requested
if [ "$BACKUP" = true ]; then
    backup_file=$(create_backup)
    if [ $? -ne 0 ]; then
        echo "Failed to create backup. Aborting."
        exit 1
    fi
fi

# Confirm unenrollment unless forced
if [ "$FORCE" != true ]; then
    echo "This will unenroll this ChromeOS device from enterprise management."
    echo "This action may violate your organization's policies."
    echo "The device will need to be re-enrolled to access managed resources."
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Unenrollment cancelled by user"
        echo "Unenrollment cancelled."
        exit 0
    fi
fi

# Perform unenrollment
perform_chromeos_unenrollment
exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "ChromeOS unenrollment completed successfully."
    echo "Please restart the device to complete the process."
    if [ "$BACKUP" = true ]; then
        echo "Backup saved to: $backup_file"
    fi
else
    echo "Unenrollment failed. Check logs for details."
fi

exit $exit_code
