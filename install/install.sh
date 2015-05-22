#!/bin/sh
#======================================================================
#
# 0. Startup
#
#======================================================================

# Pointer to file loader script - takes the current path as argument
config_files="src/config/file-tree.sh"
user_config="$PWD/user.cfg"

# Load user-defined variables
source $user_config

if [ $? -ne 0 ]; then
  echo "Problem occured when loading user-define variables file: $user_config. Exiting.."
  exit 1
fi
echo "Load user-defined variables: OK"

# Load file names
source $config_files $PWD

if [ $? -ne 0 ]; then
  echo "Problem occurred when running startup shell file: $config_files. Exiting.."
  exit 1
fi
echo "Load file names and structure: OK"

# Load colours
source $utility_colours

if [ $? -ne 0 ]; then
  echo "Problem occurred when running startup shell file: $utility_colours. Exiting.."
  exit 1
fi
echo "Load colours: OK"

# Define log functions
source $config_log $logfile $log_colour

if [ $? -ne 0 ]; then
  echo "Problem occurred when running startup shell file $config_log. Exiting.."
  exit 1
fi
echo "Load log-functions: OK"

# Setup log - open log
logsetup

if [ $? -ne 0 ]; then
  echo "Problem occurred when setting up log with function: logsetup. Exiting.."
  exit 1
fi
echo "Setup log: OK"

# Define functions runCommand, try, yell
source $utility_helpers

if [ $? -ne 0 ]; then
  echo "Problem occurred when running startup shell file: $utility_helpers. Exiting.."
  exit 1
fi
echo "Load utility functions: OK"

### We use try(runCommand (command, log_message)) from now on
log "#==================================================================#"
log "#                                                                  #"
log "Configuration for Virtual-Openstack @ CentOS7 loaded successfully!"
log "Log opened at $(date)"
log "#                                                                  #"
log "#==================================================================#"

#======================================================================
#
# 1. Libvirt
#
#======================================================================

# Generate MACS and constants
try runCommand "source $config_constants $utility_macgen" "Generate MACS"

# Check that the necessary software - libvirt - is installed
#
# CODE NEEDED HERE
#
#

# Create data network in libvirt
# if given network exists exit
virsh -c $kvm_uri net-info $data_network_name
if [ $? -eq 0 ]
  then
    log "Test if name '$data_network_name' for data network is available: $SFAILED."
    log "Network '$data_network_name' exists. Please define a different name in file '$user_config' and try again."
    exit 1
  else
    log "Test if name '$data_network_name' for data network is available: $SOK"
fi

#
# CODE REMAKE NEEDED STARTING HERE
#

# Put in xml file the variables
## Edit the name
try runCommand "sed -i \"s|<name>.*|<name>$data_network_name</name>|\" $xml_data_network" "Edit data network xml file - network name"

## Edit the ip for network node
try runCommand "sed -i \"s|.*ip='10.0.0.21'|\t<host mac='$mac_network_data' name='$vm_network_name' ip='10.0.0.21'|\" $xml_data_network" "Edit data network xml file, add mac and name - network"

## Edit the ip for the compute1 node
try runCommand "sed -i \"s|.*ip='10.0.0.31'|\t<host mac='$mac_compute1_data' name='$vm_compute1_name' ip='10.0.0.31'|\" $xml_data_network" "Edit data network xml file, add mac and name - compute1"

## Create and start the network
try runCommand "virsh -c $kvm_uri net-define $xml_data_network" "Create network $data_network_name"
try runCommand "virsh -c $kvm_uri net-start $data_network_name" "Start network $data_network_name"
try runCommand "virsh -c $kvm_uri net-autostart $data_network_name" "Add data network to autostart"

# Reset template


# Edit default network 
## The Ip for the controller
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_controller_default' name='$vm_controller_name' ip='$vm_controller_ip_eth0'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add controller node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add controller node ip: $SOK"
fi


## The Ip for the network
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_network_default' name='$vm_network_name' ip='$vm_network_ip_eth0'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add network node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add network node ip: $SOK"
fi

# The Ip for the compute1
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_compute1_default' name='$vm_compute1_name' ip='$vm_network_ip_eth0'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add compute1 node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add compute1 node ip: $SOK"
fi

#
# CODE REMAKE NEEDED ENDING HERE
#

# Restart the network default
try runCommand "virsh -c $kvm_uri net-destroy default && virsh -c $kvm_uri net-start default" "Restart network default"

#=======================================================================
#
# 2. Vm Creation
#
#=======================================================================

# Create base vm w/ kickstart
log "Creating base vm..."

#echo "command = $vm_base_name $vm_base_size $mac_base $vm_base_ram $vm_base_vcpus $kickstart_file $kvm_uri $img_disk_path"

try runCommand "source $virt_create_vm $vm_base_name $vm_base_size $mac_base $vm_base_ram $vm_base_vcpus $kickstart_file $kvm_uri $img_disk_path" "Create Base vm"

if [ $result -eq 1 ]; then
  exit 1
fi


# Snapshot
try runCommand "virsh -c $kvm_uri snapshot-create-as $vm_base_name fresh_install \"Centos 7 Base VM\" --atomic --reuse-external" "$vm_base_name - Create snapshot fresh install"

# Prep Clone
try runCommand "sudo virt-sysprep -c $kvm_uri -d $vm_base_name --firstboot-command \"echo 'HWADDR=' | cat - /sys/class/net/eth0/address | tr -d '\n' | sed 'a\\' >> /etc/sysconfig/network-scripts/ifcfg-eth0\"" "Prepare base VM for cloning - virt-sysprep"

# Clone

## Into Controller
log "Cloning base vm into controller vm..."
try runCommand "source $virt_clone_vm $vm_base_name $vm_controller_name $mac_controller_default $kvm_uri $img_disk_path" "Clone into controller - $vm_controller_name"

## Into Network
log "Cloning base vm into network vm..."
try runCommand "source $virt_clone_vm $vm_base_name $vm_network_name $mac_network_default $kvm_uri $img_disk_path" "Clone into network - $vm_network_name"

## Into Compute1
log "Cloning base vm into compute1 vm..."
try runCommand "source $virt_clone_vm $vm_base_name $vm_compute1_name $mac_compute1_default $kvm_uri $img_disk_path" "Clone into compute1 - $vm_compute1_name"

# Start Domains
try runCommand "virsh -c $kvm_uri start $vm_controller_name" "Start Controller VM - Write HWADDR in ifcfg-eth0"
try runCommand "virsh -c $kvm_uri start $vm_network_name" "Start Network VM - Write HWADDR in ifcfg-eth0"
try runCommand "virsh -c $kvm_uri start $vm_compute1_name" "Start Compute1 VM - Write HWADDR in ifcfg-eth0"

# Wait for Domains to start - 10 seconds
sleep 10
log "Waiting 10 seconds for vms to start safely.."

# Shutdown
try runCommand "virsh -c $kvm_uri shutdown $vm_controller_name" "Shutdown Controller VM"
try runCommand "virsh -c $kvm_uri shutdown $vm_network_name" "Shutdown Network VM"
try runCommand "virsh -c $kvm_uri shutdown $vm_compute1_name" "Shutdown Compute1 VM"

sleep 10
log "Waiting 10 seconds for vms to shutdown safely.."

# Add NICS of data network to network and compute1
log "Adding network-interfaces for $network_data_name network in network and compute1 nodes.."
## Add NIC 2 to network node
try runCommand "source $virt_add_nic $vm_network_name $data_network_name $mac_network_data" "Network VM - Add second network interface for data network"

## Add NIC 2 to compute1 node
try runCommand "source $virt_add_nic $vm_compute1_name $data_network_name $mac_compute1_data" "Compute1 VM - Add second network interface for data network"

# Start Domains
try runCommand "virsh -c $kvm_uri start $vm_controller_name" "Start Controller VM - Load eth0"
try runCommand "virsh -c $kvm_uri start $vm_network_name" "Start Network VM - Load eth0 and configure eth1"
try runCommand "virsh -c $kvm_uri start $vm_compute1_name" "Start Compute1 VM - Load eth0 and configure eth1"

# Wait for Domains to start - 10 seconds
sleep 10
log "Waiting 10 seconds for vms to start safely.."

# Now I can run commands remotely on the VMs using ssh

# Setup ssh keys so we can run commands over ssh without prompting for password
##  Do not create it if it exists already
if [ ! -f ~/.ssh/$ssh_key_name ]; then
  log "A ssh key with the name '$ssh_key_name' already exists. Using the existing one.."
else
  try runCommand "ssh-keygen -t rsa -N \"\" -f $ssh_key_name" "Generate ssh key for accessing vms automatically"
fi

# Copy key into servers - use same key, no need for different keys - virtual environment thus this is
# the single point of access to it
# Keys for root access
try runCommand "ssh-copy-id -i ~/.ssh/$ssh_key_name.pub root@$vm_controller_ip_eth0" "Controller VM: Install ssh key"
try runCommand "ssh-copy-id -i ~/.ssh/$ssh_key_name.pub root@$vm_network_ip_eth0" "Network VM: Install ssh key"
try runCommand "ssh-copy-id -i ~/.ssh/$ssh_key_name.pub root@$vm_compute1_ip_eth0" "Compute1 VM: Install ssh key"

try runCommand "exec ssh-agent bash" "Load ssh-agent"
try runCommand "ssh-add ~/.ssh/$ssh_key_name" "Add generated ssh-key to ssh-agent"

# Find a way to test if this succedded - else we gotta exit cause we cant send commands to vms
#
#  CODE NEEDED HERE
#
#

# Configure eth1 on network and compute1 nodes
## On Network node
try runCommand "ssh root@$vm_network_ip_eth0 'cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1" "Network VM - create ifcfg-eth1"

try runCommand "ssh root@$vm_network_ip_eth0 'sed -i \"s:HWADDR=*:HWADDR=$mac_network_data:\" /etc/sysconfig/network-scripts/ifcfg-eth1'" "Network VM - edit ifcfg-eth1, field HWADDR"

try runCommand "ssh root@$vm_network_ip_eth0 'sed -i \"s:eth0:eth1:\" /etc/sysconfig/network-scripts/ifcfg-eth1'" "Network VM - edit ifcfg-eth1, field NAME"

try runCommand "ssh root@$vm_network_ip_eth0 'sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1'" "Network VM - edit ifcfg-eth1, remove UUID"

try runCommand "ssh root@$vm_network_ip_eth0 'ifup eth1'" "Network VM - bring interface eth1 up"

## On Compute node

try runCommand "ssh root@$vm_compute1_ip_eth0 'cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1" "Compute1 VM - create ifcfg-eth1"

try runCommand "ssh root@$vm_compute1_ip_eth0 'sed -i \"s:HWADDR=*:HWADDR=$mac_compute1_data:\" /etc/sysconfig/network-scripts/ifcfg-eth1'" "Compute1 VM - edit ifcfg-eth1, field HWADDR"

try runCommand "ssh root@$vm_compute1_ip_eth0 'sed -i \"s:eth0:eth1:\" /etc/sysconfig/network-scripts/ifcfg-eth1'" "Compute1 VM - edit ifcfg-eth1, field NAME"

try runCommand "ssh root@$vm_compute1_ip_eth0 'sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1'"  "Compute1 VM - edit ifcfg-eth1, remove UUID"

try runCommand "ssh root@$vm_compute1_ip_eth0 'ifup eth1'" "Compute1 VM - bring interface eth1 up"

# Take Snapshots

try runCommand "virsh -c $kvm_uri snapshot-create-as $vm_controller_name fresh_clone \"Centos 7 Controller VM\" --atomic --reuse-external" "$vm_controller_name - Create snapshot fresh cloning"

try runCommand "virsh -c $kvm_uri snapshot-create-as $vm_network_name fresh_clone \"Centos 7 Network VM\" --atomic --reuse-external" "$vm_network_name - Create snapshot fresh cloning"

try runCommand "virsh -c $kvm_uri snapshot-create-as $vm_compute1_name fresh_clone \"Centos 7 Compute1 VM\" --atomic --reuse-external" "$vm_compute1_name - Create snapshot fresh cloning"

# Configure ntp in openstack vms, controller - master, rest - slaves

##Controller
#try runCommand "ssh $root@vm_controller_ip_eth0 'bash -s' < $os_set_ntp 1" "Controller VM - Configure ntp"

##Network
#try runCommand  "ssh $root@vm_network_ip_eth0 'bash -s' < $os_set_ntp 0 $vm_controller_ip_eth0" "Network VM - Configure ntp"

##Compute1
#try runCommand  "ssh $root@vm_compute1_ip_eth0 'bash -s' < $os_set_ntp 0 $vm_controller_ip_eth0" "Compute1 VM - Configure ntp"


#======================================================================
#
# 3. Install Openstack
#
#======================================================================
#user="admin"

# Install openstack using packstack w/predefined answers-file
#try runCommand "ssh $user@192.168.122.11 'sudo yum install -y https://rdoproject.org/repos/rdo-release.rpm'"
#try runCommand "ssh $user@192.168.122.11 'packstack --allinone'"


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
