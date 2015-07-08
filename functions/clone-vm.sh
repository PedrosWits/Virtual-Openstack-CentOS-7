#!/bin/bash
# Virt install time2goHam


function clone_vm {

  if [ $# -lt 3 ]
    then
      echo "Wrong usage. Inputs: original_vm_name new_vm_name new_mac kvm_uri disk_path"
      exit 1
  fi

  old_name=$1
  new_name=$2
  mac=$3

  if [ -z $4 ]
    then
      kvm_uri="qemu:///system"
    else
      kvm_uri=$4
  fi

  if [ -z $5 ]
    then 
      disk_path="/var/lib/libvirt/images"
    else
     disk_path=$5
  fi

  virt-clone \
    --force \
    --connect $kvm_uri \
    --original $old_name \
    --name $new_name \
    --mac $mac \
    --file $disk_path/$new_name.img

}
