#!/bin/bash
# Bootproto = none

#Inputs: 
# 1. iface name
# 2. Ip addr
# 3. Netmask
# 4. Gateway (optional)
# 5. DNS (optional)

name=$1
bridge_name=$2

ifile="/etc/sysconfig/network-scripts/ifcfg-$name"

if [ -f $ifile ]; then
  truncate -s0 $ifile
else
  touch $ifile
fi

# Device
echo "DEVICE=$name" | tee --append $ifile

# DeviceType
echo "DEVICETYPE=ovs" | tee --append $ifile

# Type
echo "TYPE=OVSPort" | tee --append $ifile

# OVS_Bridge
echo "OVS_BRIDGE=$bridge_name" | tee --append $ifile

# Bootproto
echo "BOOTPROTO=none" | tee --append $ifile

# On Boot
echo "ONBOOT=yes" | tee --append $ifile


