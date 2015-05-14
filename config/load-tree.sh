#!/bin/sh
# 
# Name: load-tree.sh
#
# Author: Pedro P. Silva

path=$1

# Load Directory Names
dir_scripts="script"
dir_kickstarts="kickstart"
dir_configs="config"

# Load Files from Directory - Scripts
sh_macgen_kvm="$path/$dir_scripts/macgen-kvm.sh"
sh_gen_const="$path/$dir_scripts/gen-constants.sh"

# Load Files from Directory - Config
config_colors="$path/$dir_configs/load-colors.sh"
config_log="$path/$dir_configs/setup-log.sh"
config_helpers="$path/$dir_configs/load-helpers.sh"

# Load Files from Directory - Kickstart
ks_generic_centos7="$path/$dir_kickstarts/generic-kickstart.cfg"

# Log File name
logfile="$path/install.log"
log_color="r" 
#r-red, b-blue, k-black, y-yellow, g-green, c-cyan, w-white

# Load Colors
source $config_colors 
# Setup Log
source $config_log $logfile $log_color
logsetup
# Load helper functions
source $config_helpers
