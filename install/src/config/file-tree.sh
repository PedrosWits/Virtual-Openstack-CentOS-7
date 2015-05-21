#!/bin/sh
# 
# Name: load-tree.sh
#
# Author: Pedro P. Silva

# Main directory

path=$1

# Templates directory
dir_template="template"

# Docs directory
dir_doc="doc"

# Src directory
dir_src="src"

# Subdirectories from src
dir_src_config="config"
dir_src_utility="utility"
dir_src_virt="virt"
dir_src_openstack="openstack"

#===============================================================

# Load files from directory - main
user_config="$path/user.cfg"

#===============================================================

# Load files from Directory - template
xml_data_network="$path/$dir_template/openstack-data.xml"

#===============================================================

# Load Files from Directory - src - config
config_constants="$path/$dir_scripts/gen-constants.sh"
config_log="$path/$dir_configs/setup-log.sh"
#===============================================================

# Load Files from Directory - src - utility
utility_macgen="$path/$dir_src/$dir_utility/macgen-kvm.sh"
utility_helpers="$path/$dir_src/$dir_utility/helpers.sh"
utility_colours="$path/$dir_src/$dir_utility/colours.sh"

#===============================================================

# Load Files from Directory - src - virt
virt_create_vm="$path/$dir_src/$dir_virt/create-vm-ks.sh"
virt_add_nic="$path/$dir_src/$dir_virt/add-net-interface.sh"
virt_clone_vm="$path/$dir_src/$dir_virt/clone-vm.sh"

#===============================================================

# Load Files from Directory - src - openstack

os_set_ntp="$path/$dir_src/$dir_openstack/set-ntp-dcc.sh"
#===============================================================

