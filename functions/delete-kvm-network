#!/bin/bash
#
# Info: very basic implementation of this feature.

function delete_net {

network_name=$1
kvm_uri=$2

# Destory domain (stop if running)
virsh -c $kvm_uri net-destroy $network_name || true

# Undefine domain
virsh -c $kvm_uri net-undefine $network_name
}
