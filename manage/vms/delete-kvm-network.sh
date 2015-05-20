#!/bin/bash
#
# Info: very basic implementation of this feature.

network_name=$1
kvm_uri="qemu:///system"

# Destory domain (stop if running)
virsh -c $kvm_uri net-destroy $network_name

# Undefine domain
virsh -c $kvm_uri net-undefine $network_name
