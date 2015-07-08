#!/bin/bash
# Virt install time2goHam

function remove_interface {

if [ $# -ne 3 ]
  then
    echo "Wrong usage, do: domain mac kvm_uri"
    exit 1
fi

domain=$1
mac=$2
kvm_uri=$3

virsh -c $kvm_uri detach-interface \
 --domain $domain \
 --type network \
 --mac $mac
}
