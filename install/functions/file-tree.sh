#!/bin/sh
# 
# Name: load-tree.sh
#
# Author: Pedro P. Silva

# Main directory

path=$1
parent_path="$(dirname "$path")"

# On Parent Directory - manage directory
dir_par_manage="manage"
dir_par_manage_vms="vms"

# Templates directory
dir_template="templates"

# Docs directory
#dir_doc="doc"

# Src directory
dir_src="functions"

# Subdirectories from src
#dir_src_config="config"
#dir_src_utility="utility"
#dir_src_virt="virt"
#dir_src_openstack="openstack"

#===============================================================

# Load files from Directory - template
xml_isolated_network="$path/$dir_template/isolated-network.xml"
xml_nat_network="$path/$dir_template/nat-network.xml"
template_kickstart="$path/$dir_template/generic-centos7.ks"
#===============================================================

# Load Files from Directory - src - config
config_constants="$path/$dir_src/gen-constants.sh"
config_log="$path/$dir_src/setup-log.sh"
#===============================================================

# Load Files from Directory - src - utility
utility_macgen="$path/$dir_src/macgen-kvm.sh"
utility_helpers="$path/$dir_src/helpers.sh"
utility_colours="$path/$dir_src/colours.sh"

#===============================================================

# Load Files from Directory - src - virt
virt_create_vm="$path/$dir_src/create-vm-ks.sh"
virt_add_nic="$path/$dir_src/add-net-interface.sh"
virt_clone_vm="$path/$dir_src/clone-vm.sh"

#===============================================================

# Load Files from Directory - src - openstack

os_set_ntp="$path/$dir_src/set-ntp-dcc.sh"
#===============================================================

# Load Files from Parent Directory - Manage - Vms
manage_vms_delete_vm="$parent_path/$dir_par_manage/$dir_par_manage_vms/delete-vm.sh"
manage_vms_delete_net="$parent_path/$dir_par_manage/$dir_par_manage_vms/delete-kvm-network.sh"
manage_vms_reset_default="$parent_path/$dir_par_manage/$dir_par_manage_vms/reset-default-net.sh"
