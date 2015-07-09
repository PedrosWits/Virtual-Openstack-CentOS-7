#!/bin/bash
# Bootproto = none

#Inputs: 
# 1. iface name
# 2. Ip addr
# 3. Netmask
# 4. Gateway (optional)
# 5. DNS (optional)

name=$1
ip=$2
netmask=$3
gateway=$4
dns=$5

ifile="/etc/sysconfig/network-scripts/ifcfg-$name"

if [ -f $ifile ]; then
  truncate -s0 $ifile
else
  touch $ifile
fi

# Write HWADDR as seen in sys class file
echo "HWADDR=" | 
cat - /sys/class/net/$name/address | 
tr -d '\n' | 
sed 'a\' |
tee --append $ifile

# Bootproto
echo "BOOTPROTO=none" | tee --append $ifile

# On Boot
echo "ONBOOT=yes" | tee --append $ifile

# UUID
echo "UUID=\"$(uuidgen)\"" | tee --append $ifile

# NAME
echo "TYPE=ETHERNET" | tee --append $ifile

# NAME
echo "NAME=\"$name\"" | tee --append $ifile

# IPADDR
echo "IPADDR=$ip" | tee --append $ifile

# Netmask
echo "NETMASK=$netmask" | tee --append $ifile

# Gateway
if [ ! -z $gateway ]; then
echo "GATEWAY=$gateway" | tee --append $ifile
fi

#DNS1
if [ ! -z $dns ]; then
echo "DNS1=$dns" | tee --append $ifile
fi

