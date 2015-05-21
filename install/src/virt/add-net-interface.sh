#!/bin/bash
# Virt install time2goHam

script_name="add-net-interface.sh"
usage="$script_name domain network mac"

if [ $# -ne 3 ]
  then
    echo $usage
    exit 1
fi

domain=$1
network=$2
mac=$3

virsh attach-interface \
  --domain $domain \
  --type network \
  --source $network \
  --mac $mac \
  --config
