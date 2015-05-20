#!/bin/sh
#======================================================================
#
# 0. Startup
#
#======================================================================

# Pointer to file loader script - takes the current path as argument
startup="config/load-tree.sh"

# Load file names, setup log and define helper functions
if ! eval source "$startup $PWD"
  then 
    echo "Failed to run startup files. Exiting"
    exit 1
  else
    log "Load file structure and setup log: $SOK"
fi

### We use try(runCommand (command, log_message)) from now on
log "#==================================================================#"
log "#                                                                  #"
log "Configuration for Virtual-Openstack @ CentOS7 loaded successfully!"
log "Log opened at $(date)"
log "#                                                                  #"
log "#==================================================================#"

# Load user-defined variables
try runCommand "source $user_config" "Read user defined variables"

#======================================================================
#
# 1. Libvirt
#
#======================================================================

# Generate MACS and constants
try runCommand "source $sh_gen_const $sh_macgen_kvm" "Generate MACS"

# Check that the necessary software - libvirt - is installed



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

# Edit default network 
## The Ip for the controller
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_controller_default' name='$vm_controller_name' ip='192.168.122.11'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add controller node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add controller node ip: $SOK"
fi


## The Ip for the network
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_network_default' name='$vm_network_name' ip='192.168.122.21'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add network node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add network node ip: $SOK"
fi

# The Ip for the compute1
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_compute1_default' name='$vm_compute1_name' ip='192.168.122.31'/>\"" virsh -c qemu:///system net-edit default

if [ $? -ne 0 ]
 then
   log "Edit network default - add compute1 node ip: $SFAILED"
   log "Can't continue. Exiting.."
   exit 1
 else 
   log "Edit network default - add compute1 node ip: $SOK"
fi

# Restart the network default
try runCommand "virsh -c $kvm_uri net-destroy default && virsh -c $kvm_uri net-start default" "Restart network default"

#=======================================================================
#
# 2. Vm Creation
#
#=======================================================================

# Create base vm w/ kickstart
log "Creating base vm..."

try runCommand "source $sh_create_vm $vm_base_name $vm_base_size $mac_base $vm_base_ram $vm_base_vcpus $ks_generic_centos7 $kvm_uri $img_disk_path" "Create Base vm"

# Snapshot
try runCommand "virsh -c $kvm_uri snapshot-create-as $vm_base_name fresh_install \"Centos 7 Base VM\" --atomic --reuse-external" "$vm_base_name - Create snapshot fresh install"

# Prep Clone
try runCommand "sudo virt-sysprep -c $kvm_uri -d $vm_base_name" "Prepare base VM for cloning - virt-sysprep"

# Clone

## Into Controller
log "Cloning base vm into controller vm..."
try runCommand "source $sh_clone_vm $vm_base_name $vm_controller_name $mac_controller_default $kvm_uri $img_disk_path" "Clone into controller - $vm_controller_name"

## Into Network
log "Cloning base vm into network vm..."
try runCommand "source $sh_clone_vm $vm_base_name $vm_network_name $mac_network_default $kvm_uri $img_disk_path" "Clone into network - $vm_network_name"

## Into Compute1
log "Cloning base vm into compute1 vm..."
try runCommand "source $sh_clone_vm $vm_base_name $vm_compute1_name $mac_compute1_default $kvm_uri $img_disk_path" "Clone into compute1 - $vm_compute1_name"

# Add NICS of data network to network and compute1
## Add NIC 2 to network node
try runCommand "source $sh_add_nic $vm_network_name $data_network_name $mac_network_data"

## Add NIC 2 to compute1 node
try runCommand "source $sh_add_nice $vm_compute1_name $data_network_name $mac_compute1_data"

# Start Domains
try runCommand "virsh -c $kvm_uri start $vm_controller_name"
try runCommand "virsh -c $kvm_uri start $vm_network_name"
try runCommand "virsh -c $kvm_uri start $vm_compute1_name"

# Feed specific configuration script to each through ssh (ntp, ..)
#try runCommand "ssh $user@192.168.122.11 'bash -s'"


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
