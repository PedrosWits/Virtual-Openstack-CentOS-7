#!/bin/sh
#======================================================================
#
# 0. Startup
#
#======================================================================
# Prog Name
prog_name="Centos7 Virtual Openstack"
# Checkpoint variable for cleanup function
checkpoint=0 

# Set -e : Script exits on a command returning error
set -e

# OK, FAILED STRINGS
SOK="\e[0;32m[OK]\e[0m"
SFAILED="\e[0;31m[FAILED]\e[0m"

# Log function
log_tag="\e[0;36m[$prog_name]\e[0m"
function log { 
  echo -n -e "$log_tag $*"
}
function ok {
   echo -e -n "$SOK\n"
}

# Clean_up function
function cleanup {
   echo -e -n "$SFAILED\n"
   case $checkpoint in 
	0)  ;;
	1)  ;;
      	2)  ;;
        *) echo "Something went wrong - checkpoint out of depth!"
   esac
   
}
# Define trap
trap cleanup EXIT SIGHUP SIGINT SIGTERM

# Pointer to file loader script - takes the current path as argument
config_files="src/config/file-tree.sh"
user_config="$PWD/user.cfg"

log "$prog_name starting on $(date).\n"
echo -e "$log_tag #==================================================================#"
# Load user-defined variables
log "Load variables from user-editable file - $user_config.. "
source $user_config
ok

# Load file names
log "Load file names and structure.. "
source $config_files $PWD 
ok

exit 0
#======================================================================
#
# 1. Libvirt
#
#======================================================================
checkpoint=1

# Generate MACS and constants
log "Generate MACs.. "
source $config_constants $utility_macgen
ok

# Check that the necessary software - libvirt - is installed
#
# CODE NEEDED HERE
#
#

# Create data network in libvirt
# if given network exists exit
log "Test if name '$data_network_name' for data network is available.. "
virsh -c $kvm_uri net-info $data_network_name
ok

#
# CODE REMAKE NEEDED STARTING HERE
#

# Put in xml file the variables
## Edit the name
log "Edit data network xml file - network name.. "
sed -i "s|<name>.*|<name>$data_network_name</name>|" $xml_data_network
ok

## Edit the ip for network node
log "Edit data network xml file, add mac and name - network.. "
sed -i "s|.*ip='10.0.0.21'|<host mac='$mac_network_data' name='$vm_network_name' ip='10.0.0.21'|" $xml_data_network
ok

## Edit the ip for the compute1 node
log "Edit data network xml file, add mac and name - compute1.. "
sed -i "s|.*ip='10.0.0.31'|\t<host mac='$mac_compute1_data' name='$vm_compute1_name' ip='10.0.0.31'|" $xml_data_network
ok

## Create and start the network
log "Create network $data_network_name.. "
virsh -c $kvm_uri net-define $xml_data_network
ok

log "Start network $data_network_name.. "
virsh -c $kvm_uri net-start $data_network_name
ok

log "Add data network to autostart.. "
virsh -c $kvm_uri net-autostart $data_network_name
ok

# Reset template

# Edit default network 
## The Ip for the controller
log "Edit network default - add controller node ip.. "
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_controller_default' name='$vm_controller_name' ip='$vm_controller_ip_eth0'/>\"" virsh -c $kvm_uri net-edit default
ok

## The Ip for the network
log "Edit network default - add network node ip.. "
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_network_default' name='$vm_network_name' ip='$vm_network_ip_eth0'/>\"" virsh -c $kvm_uri net-edit default
ok

# The Ip for the compute1
log "Edit network default - add compute1 ip.. "
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_compute1_default' name='$vm_compute1_name' ip='$vm_network_ip_eth0'/>\"" virsh -c $kvm_uri net-edit default
ok

#
# CODE REMAKE NEEDED ENDING HERE
#

# Restart the network default
log "Restart network default.. "
virsh -c $kvm_uri net-destroy default && virsh -c $kvm_uri net-start default
ok

#=======================================================================
#
# 2. Vm Creation
#
#=======================================================================
checkpoint=2

# Create base vm w/ kickstart
log "Creating base vm - this may take a while... "
source $virt_create_vm $vm_base_name $vm_base_size $mac_base $vm_base_ram $vm_base_vcpus $kickstart_file $kvm_uri $img_disk_path
ok

# Snapshot
log "$vm_base_name - Create snapshot fresh install.. "
virsh -c $kvm_uri snapshot-create-as $vm_base_name fresh_install "Centos 7 Base VM" \
--atomic --reuse-external
ok

# Prep Clone
log "Prepare base VM for cloning - virt-sysprep.. "

sudo virt-sysprep -c $kvm_uri -d $vm_base_name \
--firstboot-command "echo 'HWADDR=' | cat - /sys/class/net/eth0/address | tr -d '\n' | sed 'a\\' >> /etc/sysconfig/network-scripts/ifcfg-eth0"

ok
# Clone

## Into Controller
log "Cloning base vm into controller vm.. "
source $virt_clone_vm $vm_base_name $vm_controller_name $mac_controller_default $kvm_uri $img_disk_path
ok

## Into Network
log "Cloning base vm into network vm.. "
source $virt_clone_vm $vm_base_name $vm_network_name $mac_network_default $kvm_uri $img_disk_path
ok

## Into Compute1
log "Cloning base vm into compute1 vm.. "
source $virt_clone_vm $vm_base_name $vm_compute1_name $mac_compute1_default $kvm_uri $img_disk_path
ok

# Start Domains
log "Starting VMs - Write HWADDR in ifcfg-eth0 with first-boot.. "
virsh -c $kvm_uri start $vm_controller_name
virsh -c $kvm_uri start $vm_network_name
virsh -c $kvm_uri start $vm_compute1_name
ok

# Wait for Domains to start - 10 seconds
sleep 10
log "Waiting 10 seconds for vms to start safely.."

# Shutdown
log "Shutting down VMs for offline network configuration.. "
virsh -c $kvm_uri shutdown $vm_controller_name
virsh -c $kvm_uri shutdown $vm_network_name
virsh -c $kvm_uri shutdown $vm_compute1_name
ok

log "Waiting 10 seconds for vms to shutdown safely.."
sleep 10
ok

# Add NICS of data network to network and compute1
log "Adding network-interfaces for $network_data_name network in network and compute1 nodes.."
## Add NIC 2 to network node
source $virt_add_nic $vm_network_name $data_network_name $mac_network_data
## Add NIC 2 to compute1 node
source $virt_add_nic $vm_compute1_name $data_network_name $mac_compute1_data
ok

# Start Domains
log "Re-starting the VMs.. "
try runCommand "virsh -c $kvm_uri start $vm_controller_name" "Start Controller VM - Load eth0"
try runCommand "virsh -c $kvm_uri start $vm_network_name" "Start Network VM - Load eth0 and configure eth1"
try runCommand "virsh -c $kvm_uri start $vm_compute1_name" "Start Compute1 VM - Load eth0 and configure eth1"
ok

# Wait for Domains to start - 10 seconds
log "Waiting 10 seconds for vms to shutdown safely.."
sleep 10
ok

# Now I can run commands remotely on the VMs using ssh
# Setup ssh keys so we can run commands over ssh without prompting for password
##  Do not create it if it exists already

log "Generate ssh key for accessing the VMs automatically.. "
if [ ! -f ~/.ssh/$ssh_key_name ]; then
  log "A ssh key with the name '$ssh_key_name' already exists. Using the existing one.. "
else
  ssh-keygen -t rsa -N \"\" -f $ssh_key_name
fi
ok

# Create local ~/.ssh/config if not exists and add the option 'StrictHostKeyChecking no' to force first-time ssh inyes/no question to be automatically answered
log "Add VMs to the list of known_hosts, by using key-scan.. "
ssh-keyscan -t rsa,dsa $vm_controller_ip_eth0 >> ~/.ssh/known_hosts
ssh-keyscan -t rsa,dsa $vm_network_ip_eth0 >> ~/.ssh/known_hosts
ssh-keyscan -t rsa,dsa $vm_compute1_ip_eth0 >> ~/.ssh/known_hosts
ok

# Copy key into servers - use same key, no need for different keys - virtual environment thus this is
# the single point of access to it
# Keys for root access
log "Install the keys onto the VMs.. "
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_controller_ip_eth0
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_network_ip_eth0
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_compute1_ip_eth0
ok

log "Add generated ssh-key to ssh-agent.. "
exec ssh-agent bash
ssh-add ~/.ssh/$ssh_key_name
ok

# Find a way to test if this succedded - else we gotta exit cause we cant send commands to vms
# use timeout in ssh - if it fails then we gotta exit - delete all vms? 

log "Check if ssh-configuration was successfull.. "
ssh -o ConnectionTimeout=5 -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 'exit'
ssh -o ConnectionTimeout=5 -o BatchMode=yes $vm_user@$vm_network_ip_eth0 'exit'
ssh -o ConnectionTimeout=5 -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 'exit'
ok

# Configure eth1 on network and compute1 nodes
## On Network node
log "Configure data network on VMs - eth1 on Network VM.. "

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|HWADDR=.*|HWADDR=$mac_network_data|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|eth0|eth1|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo ifup eth1"

ok
## On Compute node
log "Configure data network on VMs - eth1 on Compute1 VM.. "

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"s|HWADDR=.*|HWADDR=$mac_compute1_data|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"s|eth0|eth1|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo ifup eth1"

ok

# Take Snapshots
log "Take snapshots of VMs after fresh clone.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "fresh_clone" "Centos 7 Controller VM" \
--atomic --reuse-external

virsh -c $kvm_uri snapshot-create-as $vm_network_name "fresh_clone" "Centos 7 Network VM" \
 --atomic --reuse-external

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "fresh_clone" "Centos 7 Compute1 VM" \
--atomic --reuse-external

ok

# Configure ntp in openstack vms, controller - master, rest - slaves

##Controller
log "Configure and start the ntp service - Controller VM.. "

ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo bash -s" < $os_set_ntp 1

ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service"

ok
##Network
log "Configure and start the ntp service - Network VM.. "

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo bash -s" < $os_set_ntp 0 $vm_controller_ip_eth0

ssh -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service"

ok
##Compute1
log "Configure and start the ntp service - Compute1 VM.."

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo bash -s" < $os_set_ntp 0 $vm_controller_ip_eth0

ssh -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service"

ok
#======================================================================
#
# 3. Install Openstack
#
#======================================================================

# Rdo repository
log "Installing packstack on the Controller VM.. "

ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y https://rdoproject.org/repos/rdo-release.rpm"
# Install Packstack
ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y openstack-packstack"
# Openstack-Utils
ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y openstack-utils"
ok

# Generate the answers-file
ANSWERS_FILE="packstack_answers.conf"

log "Generate the answers file using packstack.. "

ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"packstack --gen-answer-file=$ANSWERS_FILE"

ok

# All in one installation at first
#log "Running packstack allinone installation - this may take a while.."
#try runCommand "ssh root@$vm_controller_ip_eth0 'packstack --allinone'" "Controller VM - Use packstack to deploy Openstack"

# Get packstack-answers file and modify it to include the remaining hosts
#local name_packstack_file
#try runCommand "name_packstack_file=$(ssh root@$vm_controller_ip_eth0 'find /home | grep packstack-answers')" "Get packstack-answers file"

# Modify with sed



# Re run packstack
log "Running packstack with configured values - this may take a while.. "

ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"packstack --answer-file=$name_packstack_file"

ok


#======================================================================
#
# 4. Install Rally and gather benchmarking data
#
#======================================================================

# Install Rally

# Run Rally

# Show results

#======================================================================
#
# 5. Finalize
#
#======================================================================

# Install openstack-management scripts

# Display useful messages
