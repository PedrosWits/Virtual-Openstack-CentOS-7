#!/bin/bash

script_name="gen-constants.sh"
usage="$script_name macgen-script"

if [ $# -ne 1 ]
  then
    echo $usage
    exit 1
fi

macgen_script=$1

mac_base=$(source $macgen_script)
mac_controller_default=$(source $macgen_script)
mac_network_default=$(source $macgen_script)
mac_network_data=$(source $macgen_script)
mac_network_external=$(source $macgen_script)
mac_compute1_default=$(source $macgen_script)
mac_compute1_data=$(source $macgen_script)
