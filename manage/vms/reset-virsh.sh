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

kvm_uri="qemu:///system"


