#!/bin/bash
# Virt install time2goHam

function create_vm {
  if [ $# -lt 7 ]; then
    echo "Wrong usage. " \
	 "Inputs: name size ram vcpus ks_file uri disk_path net1 mac1 net2 mac2"
   exit 1
  fi
  name=$1
  size=$2
  ram=$3
  vcpus=$4
  kickstart=$5
  connect_uri=$6
  img_path=$7
  net1=$8
  mac1=$9
  net2=${10}
  mac2=${11}

  virt-install \
  --connect $connect_uri \
  --virt-type kvm \
  --name=$name \
  --ram=$ram \
  --vcpus=$vcpus \
  --disk path=$img_path/$name.img,size=$size,bus=virtio,format=qcow2 \
  --initrd-inject=$kickstart \
  --location=http://mirror.catn.com/pub/centos/7/os/x86_64 \
  --extra-args="ks=file:/$kickstart text console=tty0 utf8 console=ttyS0,115200" \
  --network network=$net1,mac=$mac1 \
  --network network=$net2,mac=$mac2 \
  --os-type linux \
  --os-variant virtio26 \
  --force \
  --noreboot \
  --graphics none 
}
