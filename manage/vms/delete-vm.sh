#!/bin/bash
#
# Info: very basic implementation of this feature.
#       Assumes files are under default pool: /var/lib/libvirt/images/
#       and the img file name is the same as the domain's name


domain=$1
kvm_uri="qemu:///system"

# Destory domain (stop if running)
virsh -c $kvm_uri destroy $domain

# Undefine domain
virsh -c $kvm_uri undefine $domain --remove-all-storage --wipe-storage --snapshots-metadata --nvram

# Delete img file
#virsh -c $kvm_uri vol-delete $domain.img --pool default
