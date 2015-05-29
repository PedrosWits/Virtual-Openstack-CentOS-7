#!/bin/bash
# 
# Note: USE WITH CARE 
#
# Info: This script attempts to remove all created vms, disks and networks,
#       and reset libvirt to its initial state. May not be completely successful at this,
#       as it uses several parameters.
#
#
# Parameters: uri - default = qemu:///system
#             disk paths =
#

if [ $# -lt 1 ]
  then 
    kvm_uri="qemu:///system"
  else
    kvm_uri=$1
fi

EDITOR="sed -i \"/host mac/d\"" virsh -c $kvm_uri net-edit default

if [ $? -eq 0 ]; then
	virsh -c $kvm_uri net-destroy default
	virsh -c $kvm_uri net-start default
fi
