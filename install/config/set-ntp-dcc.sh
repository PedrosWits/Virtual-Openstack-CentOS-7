#!/bin/bash

configure_as_master=$1
ip_master=$2

ntp_slave_string="server $ip_master iburst"

ntp_controller_string="
server ntp iburst\n
server ntp01.fccn.pt iburst\n
server ntp02.fccn.pt iburst\n
\n
restrict −4 default kod notrap nomodify\n
restrict −6 default kod notrap nomodify\n
\n 
driftfile /etc/ntp/drift\n 
broadcastdelay 0.008\n
authenticate no\n
logconfig +info +events\n 
logfile /var/log/ntpd\n
enable monitor\n
enable ntp" 

if [ $configure_as_master -eq 1 ]
  then
    sudo echo -e $ntp_controller_string > /tmp/ntp.conf
  else 
    sudo echo -e $ntp_slave_string > /tmp/ntp.conf
fi
