#!/bin/bash

name1=$1
name2=$2
name3=$3

ifdown ${name1}
ifdown ${name2}

ip link set dev ${name1} name not_${name1}
ip link set dev ${name2} name ${name1}
ip link set dev not_${name1} name ${name2}

if [ ! -z "${name3}" ]; then
 ifdown ${name3}

 ip link set dev ${name2} name not_${name2}
 ip link set dev ${name3} name ${name2}
 ip link set dev not_${name2} name ${name3}
 ifup ${name3}
fi

ifup ${name1}
ifup ${name2}
