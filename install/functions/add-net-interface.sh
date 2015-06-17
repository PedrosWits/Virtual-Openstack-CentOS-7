#!/bin/bash
# Virt install time2goHam

script_name="add-net-interface.sh"
usage="$script_name domain network mac kvm_uri"

if [ $# -ne 4 ]
  then
    echo $usage
    exit 1
fi

domain=$1
network=$2
mac=$3
kvm_uri=$4

virsh -c $kvm_uri attach-interface \
  --domain $domain \
  --type network \
  --model virtio \
  --source $network \
  --mac $mac \
  --config 
