#!/bin/bash
# Virt install time2goHam

script_name="create-vm-ks.sh"
usage="USAGE $script_name: guest_name disk_size mac_address ram vcpus kickstart_file network_name connect_uri img_path"

if [ $# -lt 7 ]
  then
    echo $usage
    exit 1
fi

name=$1
size=$2
mac=$3
ram=$4
vcpus=$5
kickstart=$6
network_name=$7

if [ -z "$8" ]
  then
    connect_uri="qemu:///system"
  else
    connect_uri=$8
fi

if [ -z "$9" ]
  then
     img_path="/var/lib/libvirt/images"
  else
     img_path=$9
fi

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
  --network network=$network_name,mac=$mac \
  --os-type linux \
  --os-variant virtio26 \
  --force \
  --noreboot \
  --graphics none 

