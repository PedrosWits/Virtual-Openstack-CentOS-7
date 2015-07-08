#!/bin/bash

function add_interface {

if [ $# -ne 4 ]
  then
    echo "Wrong usage. Input is: domain network mac kvm_uri"
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
}
