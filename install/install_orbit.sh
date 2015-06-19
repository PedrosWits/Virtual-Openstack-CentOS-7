#!/bin/sh
#======================================================================
#
# INPUT ARGS
#
#======================================================================
# Usage
usage="Usage: install_orbit.sh [options]
   --clean          Clean previous installation (remove all traces) with parameters specified in vorbe.cfg
   --save-base-vm   Save base vm - used for cloning any virtual node
   --skip-base-vm   Use a saved base vm - with name specified in vorbe.cfg
   --debug          Do not clean anything in case installation fails
   --help           Prompt usage and help information"

# Default values
CLEAN=0
SKIP_VM_CREATION=0
SAVE_BASE_VM=0
DEBUG=0

while [[ $# > 0 ]]
do
key="$1"

case $key in
   --clean)
	CLEAN=1;
   ;;
   --skip-base-vm)
	SKIP_VM_CREATION=1
   ;;
   --save-base-vm)
	SAVE_BASE_VM=1
   ;;
   --debug)
        DEBUG=1
   ;;
   --help)
	echo -e "$usage"
	exit 0
   ;;
   *)
	echo "Unknown option: $key"
	echo -e "$usage"
	exit 1
   ;;

esac
shift # past argument or value
done

#======================================================================
#
# 0. Startup
#
#======================================================================
# Prog Name
prog_name="A Virtual Openstack RedHat-based Environment"
prog_sigla="orbit"
# Checkpoint variable for cleanup function
checkpoint=0 

# Set -e : Script exits on a command returning error
set -e
# Exit if trying to use an unset variable
set -u

# START TIME
START_TIME=$(date +%s%N)

# OK, FAILED STRINGS
SOK="\e[0;32m[ OK ]\e[0m"
SFAILED="\e[0;31m[ FAILED ]\e[0m"

# Log function
log_file="orbit.log"
echo "" > $log_file

log_tag="\e[0;36m[$prog_sigla]\e[0m"
function log { 
    echo -e -n "$log_tag $*" 2>&1 | tee --append $log_file
    echo ""
}
function ok {
    echo -e "$SOK" | tee --append $log_file 
}
# Function prompt yes no question
function promptyn {
  for j in 1 2 3; do
      read -t 10 -p "$1 [y/n]: " yn
      case $yn in
          [Yy]* ) return 0;;
          [Nn]* ) return 1;;
          * ) echo "Please answer yes or no.";;
      esac
  done
  return 1
}

config_files="functions/file-tree.sh"
# Pointer to file loader script - takes the current path as argument
user_config="$(pwd -P)/orbit.conf"
# Save user_config to orbit.last-config so that next clean uses the config specified before
#(else if the config file was changed it would read the new config instead
# - causing the clean to fail due to unmatched variables)
install_config="$(pwd -P)/orbit.last-install"

if [ $CLEAN -eq 0 ]; then
    cat $user_config > $install_config
    # Load user-defined variables
    log "Load variables from user-editable file - $user_config.. "
    source $user_config 
    ok

   echo ""
   echo -e "$prog_sigla: $prog_name starting on $(date)" | tee --append $log_file
   echo -e "$log_tag #==================================================================#"
   # Load file names
   log "Load file names and structure.. "
   source $config_files $(pwd -P) 
   ok
fi

# Temporary files
data_network_file="$(pwd -P)/orbit_data_network.xml"
touch $data_network_file
management_network_file="$(pwd -P)/orbit_management_network.xml"
touch $management_network_file
external_network_file="$(pwd -P)/orbit_external_network.xml"
touch $external_network_file

tmp_kickstart_file="kickstart.ks"

# Clean_up function - can only be defined after loading file names and user variables
function cleanup {
   if [ "$?" -eq 0 ]; then
   	   echo -e "$log_tag \e[0;32mInstallation successful!\e[0m" | tee --append $log_file   
   else
	   if [ $CLEAN -eq 1 ]; then
	       echo -e "$log_tag Cleaning up previous installation, with variables read from '$install_config'.. " | tee --append $log_file
	   else
               echo -e "$SFAILED" | tee --append $log_file
	       echo -e "$log_tag \e[0;31mInstallation unsuccessful!\e[0m Cleaning up.." \
		 | tee --append $log_file
	   fi
	   if [ $DEBUG -eq 0 ] || [ $CLEAN -eq 1 ]; then
		   # Reset default-net, delete data-net.
		   if [ $checkpoint -ge 1 ]; then
			    #source $manage_vms_reset_default $kvm_uri || true
			    source $manage_vms_delete_net $data_network_name $kvm_uri || true
			    source $manage_vms_delete_net $management_network_name $kvm_uri || true
			    source $manage_vms_delete_net $ext_network_name $kvm_uri || true
		   fi
		   # Delete vms created
		   if [ $checkpoint -ge 2 ]; then
			    if [ $SKIP_VM_CREATION -eq 0 ] && [ $SAVE_BASE_VM -eq 0 ]; then
				source $manage_vms_delete_vm $vm_base_name $kvm_uri || true
			    fi
			    source $manage_vms_delete_vm $vm_controller_name $kvm_uri || true
			    source $manage_vms_delete_vm $vm_network_name $kvm_uri || true
			    source $manage_vms_delete_vm $vm_compute1_name $kvm_uri || true
	           fi
		   if [ $checkpoint -ge 3 ]; then
			    # Clean known_hosts file
			    ssh-keygen -R $vm_controller_ip_eth0 || true
			    ssh-keygen -R $vm_network_ip_eth0 || true
			    ssh-keygen -R $vm_compute1_ip_eth0 || true
		   fi		   
		   ok
	   fi
   fi

   if [ $CLEAN -eq 1 ]; then
     rm -f $install_config
   else
     echo "checkpoint=$checkpoint" >> $install_config
   fi
   
   rm -f $data_network_file
   rm -f $management_network_file
   rm -f $external_network_file
   rm -f $tmp_kickstart_file
   
   END_TIME=$(date +%s%N)
   ELAPSED_TIME_MILLI=$((($END_TIME-$START_TIME)/1000000))
   ELAPSED_TIME_SEC=$(($ELAPSED_TIME_MILLI/1000))
   ELAPSED_TIME_MIN=$(($ELAPSED_TIME_SEC/60))
   echo -e "$log_tag Elapsed Time: ${ELAPSED_TIME_MIN}m $((${ELAPSED_TIME_SEC} - ${ELAPSED_TIME_MIN}*60))s" | tee --append $log_file
}
# Define trap
trap cleanup EXIT SIGHUP SIGINT SIGTERM

if [ $CLEAN -eq 1 ]; then
    source $install_config
    source $config_files $(pwd -P) 
    exit 1
fi

#=====================================================================
#
# 1. Libvirt
#
#======================================================================
# Check if virtualization is enabled
log "Check if virtualization is enabled.. "
ncpus=$(egrep -c '(svm|vmx)' /proc/cpuinfo)

if [ $ncpus -lt 1 ]; then
  log "Hardware virtualization is disabled or not supported!"
  exit -1
fi
ok

# Generate MACS and constants
log "Generate MACs.. "
mac_base=$(source $utility_macgen)
mac_controller_management=$(source $utility_macgen)
mac_network_management=$(source $utility_macgen)
mac_network_data=$(source $utility_macgen)
mac_network_external=$(source $utility_macgen)
mac_compute1_management=$(source $utility_macgen)
mac_compute1_data=$(source $utility_macgen)
ok

log "Check if required software is installed.. "

required="Required packages are not installed, please run first: 'sudo yum install kvm qemu-kvm python-virtinst libvirt libvirt-python virt-manager libguestfs-tools bridge-utils openssh'"

type virsh > /dev/null 2>&1 || echo -e "\nLibvirt not installed. $required"
type virt-install > /dev/null 2>&1 || echo -e "\nLibguestfs-tools not installed. $required"
type ssh-keygen > /dev/null 2>&1 || echo -e "\nOpenssl not installed. $required"

ok

checkpoint=1
# Create data network in libvirt
# if given network exists exit
RESULT=0

log "Test if name '$management_network_name' is available for creating the management network.. "
virsh -c $kvm_uri net-info $management_network_name && RESULT=1 || true 
if [ $RESULT -eq 1 ]; then
  exit 1
fi
ok

log "Test if name '$data_network_name' is available for creating the data network.. "
virsh -c $kvm_uri net-info $data_network_name && RESULT=1 || true 
if [ $RESULT -eq 1 ]; then
  exit 1
fi
ok

log "Test if name '$ext_network_name' is available for creating the external network.. "
virsh -c $kvm_uri net-info $ext_network_name && RESULT=1 || true 
if [ $RESULT -eq 1 ]; then
  exit 1
fi
ok

log "Read empty xml templates into temporary files.. "
cat $xml_isolated_network | tee --append $data_network_file
cat $xml_nat_network | tee --append $management_network_file
cat $xml_nat_network | tee --append $external_network_file
ok

log "Writing xml files according to configuration file.. "

#Management Network
## Edit the name
sed -i "s|<name>.*|<name>$management_network_name</name>|" $management_network_file
## Edit the bridge's name
sed -i "s|<bridge.*|<bridge name='$management_bridge_name'/>|" $management_network_file
## Edit the ip address
sed -i "s|<ip address.*|<ip address='$management_network_ip' netmask='$management_network_netmask'>|" $management_network_file
## Edit the dhcp range start-end
sed -i "s|<range.*|<range start='$management_network_ip_start' end='$management_network_ip_end'/>|" $management_network_file
## Edit the ip for network node
sed -i "/range start/a <host mac='$mac_network_management' name='$vm_network_name' ip='$vm_network_ip_eth0'/>" $management_network_file
## Edit the ip for the compute1 node
sed -i "/range start/a <host mac='$mac_compute1_management' name='$vm_compute1_name' ip='$vm_compute1_ip_eth0'/>" $management_network_file
## Edit the ip for the controller node
sed -i "/range start/a <host mac='$mac_controller_management' name='$vm_controller_name' ip='$vm_controller_ip_eth0'/>" $management_network_file

#Data Network
## Edit the name
sed -i "s|<name>.*|<name>$data_network_name</name>|" $data_network_file
## Edit the bridge's name
sed -i "s|<bridge.*|<bridge name='$data_bridge_name'/>|" $data_network_file
## Edit the ip address
sed -i "s|<ip address.*|<ip address='$data_network_ip' netmask='$data_network_netmask'>|" $data_network_file
## Edit the dhcp range start-end
sed -i "s|<range.*|<range start='$data_network_ip_start' end='$data_network_ip_end'/>|" $data_network_file
## Edit the ip for network node
sed -i "/range start/a <host mac='$mac_network_data' name='$vm_network_name' ip='$vm_network_ip_eth1'/>" $data_network_file
## Edit the ip for the compute1 node
sed -i "/range start/a <host mac='$mac_compute1_data' name='$vm_compute1_name' ip='$vm_compute1_ip_eth1'/>" $data_network_file


#External Network
## Edit the name
sed -i "s|<name>.*|<name>$ext_network_name</name>|" $external_network_file
## Edit the bridge's name
sed -i "s|<bridge.*|<bridge name='$ext_bridge_name'/>|" $external_network_file
## Edit the ip address
sed -i "s|<ip address.*|<ip address='$ext_network_ip' netmask='$ext_network_netmask'>|" $external_network_file
## Edit the dhcp range start-end
sed -i "s|<range.*|<range start='$ext_network_ip_start' end='$ext_network_ip_end'/>|" $external_network_file
## Edit the ip for network node
sed -i "/range start/a <host mac='$mac_network_external' name='$vm_network_name' ip='$vm_network_ip_eth2'/>" $external_network_file
ok

## Create and start the network
log "Create and start the network $management_network_name.. "
virsh -c $kvm_uri net-define $management_network_file 
virsh -c $kvm_uri net-start $management_network_name 
virsh -c $kvm_uri net-autostart $management_network_name 
ok

## Create and start the network
log "Create and start the network $data_network_name.. "
virsh -c $kvm_uri net-define $data_network_file 
virsh -c $kvm_uri net-start $data_network_name 
virsh -c $kvm_uri net-autostart $data_network_name 
ok

## Create and start the network
log "Create and start the network $ext_network_name.. "
virsh -c $kvm_uri net-define $external_network_file 
virsh -c $kvm_uri net-start $ext_network_name 
virsh -c $kvm_uri net-autostart $ext_network_name 
ok

#=======================================================================
#
# 2. Vm Creation
#
#=======================================================================
checkpoint=2

# Create base vm w/ kickstart
if [ $SKIP_VM_CREATION -eq 0 ]; then
	# Copy template to local
	log "Creating tmp kickstart file according to specifications.. "
	cp $template_kickstart $(pwd -P)/$tmp_kickstart_file
        # Read passwords from config file and write them in the kickstart
	
	
	ok
	# Create vm
	log "Creating base vm - this may take a while... "
	source $virt_create_vm $vm_base_name $vm_base_size $mac_base $vm_base_ram $vm_base_vcpus $tmp_kickstart_file $management_network_name $kvm_uri $img_disk_path  
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
fi


# Clone

## Into Controller
log "Cloning base vm into controller vm.. "
source $virt_clone_vm $vm_base_name $vm_controller_name $mac_controller_management $kvm_uri $img_disk_path 
ok

## Into Network
log "Cloning base vm into network vm.. "
source $virt_clone_vm $vm_base_name $vm_network_name $mac_network_management $kvm_uri $img_disk_path 
ok

## Into Compute1
log "Cloning base vm into compute1 vm.. "
source $virt_clone_vm $vm_base_name $vm_compute1_name $mac_compute1_management $kvm_uri $img_disk_path 
ok

# Start Domains
log "Starting VMs - Write HWADDR in ifcfg-eth0 with first-boot.. "
virsh -c $kvm_uri start $vm_controller_name 
virsh -c $kvm_uri start $vm_network_name 
virsh -c $kvm_uri start $vm_compute1_name 
ok

# Wait for Domains to start - 10 seconds
log "Waiting 30 seconds for vms to start and perform first-boot script safely.."
sleep 30
ok

# Shutdown
log "Shutting down VMs for offline network configuration.. "
virsh -c $kvm_uri shutdown $vm_controller_name 
virsh -c $kvm_uri shutdown $vm_network_name 
virsh -c $kvm_uri shutdown $vm_compute1_name 
ok

log "Waiting 30 seconds for vms to shutdown safely.."
sleep 30
ok

# Add NICS of data network to network and compute1
log "Adding network-interfaces for $data_network_name network in network and compute1 nodes.."
## Add NIC 2 to network node
source $virt_add_nic $vm_network_name $data_network_name $mac_network_data $kvm_uri 
## Add NIC 3 to network node
source $virt_add_nic $vm_network_name $ext_network_name $mac_network_external $kvm_uri
## Add NIC 2 to compute1 node
source $virt_add_nic $vm_compute1_name $data_network_name $mac_compute1_data $kvm_uri 
ok

# Start Domains
log "Re-starting the VMs.. "
virsh -c $kvm_uri start $vm_controller_name 
virsh -c $kvm_uri start $vm_network_name 
virsh -c $kvm_uri start $vm_compute1_name 
ok

# Wait for Domains to start - 10 seconds
log "Waiting 30 seconds for vms to start safely.."
sleep 30
ok

# Install ssh_pass if not installed
log "Check if 'sshpass' is installed.. "
if [ ! type sshpass > /dev/null 2>&1 ]; then
    sudo yum -y -q install sshpass
fi
ok

# Now I can run commands remotely on the VMs using ssh
# Setup ssh keys so we can run commands over ssh without prompting for password
##  Do not create it if it exists already

log "Generate ssh key for accessing the VMs automatically.. "
if [ -f ~/.ssh/$ssh_key_name ]; then
  log "\nA ssh key with the name '$ssh_key_name' already exists. Using the existing one.. "
else
  ssh-keygen -t rsa -N "" -f ~/.ssh/$ssh_key_name 
fi
ok

# Add vms' fingerprints to the list of known hosts if they are not there already
RESULT=0
log "Test if given Ips are available in the list of known_hosts.. "
if [ ! -f ~/.ssh/known_hosts ]; then
   touch ~/.ssh/known_hosts 
else 
  for i in 1 2 3; do
        case $i in
	  1) hosti=$vm_controller_ip_eth0;;
	  2) hosti=$vm_network_ip_eth0;;
	  3) hosti=$vm_compute1_ip_eth0;;
	  *) echo "NEVER REACHED"; exit 1;;
	esac
	# Find hosti in known_hosts
	ssh-keygen -F $hosti && RESULT=1 || true 
	  #Result=1 if found
	  if [ $RESULT -eq 1 ]; then
	     #Ask user if he wants to erase value if found. If no response exit automatically.
	     if promptyn "Hostname $hosti exists in known_hosts. Do you wish to erase it and continue?"; then
    	   	 # Erase the value from known_hosts
		 ssh-keygen -R $hosti 
             else
		exit 1
             fi
  	  fi
  done 
fi
ok

# Checkpoint=3 -> limpar known_hosts file

checkpoint=3

log "Add VMs to the list of known_hosts, by using key-scan.. "
ssh-keyscan -t rsa,dsa $vm_controller_ip_eth0 >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_network_ip_eth0 >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_compute1_ip_eth0 >> ~/.ssh/known_hosts 
ok

# Set SSHPASS environment variable to use with sshpass
log "Set SSHPASS environment variable for non-interactive ssh-copy-id. Read pass from user.cfg.. "
export SSHPASS="$vm_pass"
ok

# Copy key into servers - use same key, no need for different keys - virtual environment thus this is
# the single point of access to it
log "Install the keys onto the VMs.. "
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_controller_ip_eth0
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_network_ip_eth0
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_compute1_ip_eth0
ok

# Find a way to test if this succedded - else we gotta exit cause we cant send commands to vms
# use timeout in ssh - if it fails then we gotta exit - delete all vms? 

log "Check if ssh-configuration was successfull.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 'exit' 
ok

# Configure eth1 on network and compute1 nodes
## On Network node
log "Configure data network on VMs - eth1 on Network VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|HWADDR=.*|HWADDR=$mac_network_data|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|eth0|eth1|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"echo 'UUID=\"$(uuidgen)\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"echo 'DNS1=$management_network_ip' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo ifup eth1" 

ok

log "Configure data network on VMs - eth2 on Network VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|HWADDR=.*|HWADDR=$mac_network_external|\" /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"s|eth0|eth2|\" /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"echo 'UUID=\"$(uuidgen)\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"echo 'GATEWAY=$ext_network_ip' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo ifup eth2" 

ok

## On Compute node
log "Configure data network on VMs - eth1 on Compute1 VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"s|HWADDR=.*|HWADDR=$mac_compute1_data|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"s|eth0|eth1|\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo sed -i \"/UUID/d\" /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"echo 'UUID=\"$(uuidgen)\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"echo 'DNS1=$management_network_ip' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo ifup eth1" 

ok

# Confirm that the VMs have internet connection and can ping each other

log "Verify that VMs have internet connection.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ping -c 2 www.google.com" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"ping -c 2 www.google.com" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"ping -c 2 www.google.com" 

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

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo bash -s" < $os_set_ntp 1

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
##Network
log "Configure and start the ntp service - Network VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo bash -s" < $os_set_ntp 0 $vm_controller_ip_eth0

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
##Compute1
log "Configure and start the ntp service - Compute1 VM.."

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo bash -s" < $os_set_ntp 0 $vm_controller_ip_eth0

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_eth0 \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
#======================================================================
#
# 4. Install Openstack
#
#======================================================================

# Rdo repository
log "Installing repository on Controller.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -q -y https://rdoproject.org/repos/rdo-release.rpm"

ok

# Install Packstack

log "Installing packstack.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -q -y openstack-packstack" 
# Openstack-Utils
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -q -y openstack-utils" 
# Yum update
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum -q -y update" 

ok


# Generate the answers-file with unix timestamp
ANSWERS_FILE="packstack_answers$(date +%s).conf"

log "Generate the answers file using packstack.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"packstack --gen-answer-file=$ANSWERS_FILE"

ok

# Edit answers file using openstack-config

log "Edit answers file according to our configuration: vms ips, ntp servers, etc.. "

#ssh -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
#"openstack-config --set $ANSWERS_FILE general CONFIG_SSH_KEY /home/$vm_user/.ssh/id_rsa.pub"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_COMPUTE_HOSTS $vm_compute1_ip_eth0"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NETWORK_HOSTS $vm_network_ip_eth0"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES gre"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TYPE_DRIVERS gre"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TUNNEL_ID_RANGES 1001:2000"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_VNI_RANGES 1001:2000"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_PROVISION_DEMO n"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_TUNNEL_IF eth1"

ok

# Install root ssh keys on root user from all nodes - so that packstack can perform priveledged
# installation on these nodes from the admin user in the controller node
log "Install ssh key in root users, for automating required priveleged packstack installation.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ssh-keyscan -t rsa,dsa $vm_network_ip_eth0 >> ~/.ssh/known_hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ssh-keyscan -t rsa,dsa $vm_compute1_ip_eth0 >> ~/.ssh/known_hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo rpm -ivh http://pkgs.repoforge.org/sshpass/sshpass-1.05-1.el7.rf.x86_64.rpm"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"install -m 600 /dev/null tmp_root; echo $vm_root_pass > tmp_root"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo mkdir -p /root/.ssh/; cat ~/.ssh/id_rsa.pub | sudo tee --append /root/.ssh/authorized_keys"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sshpass -f tmp_root ssh-copy-id root@$vm_network_ip_eth0"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sshpass -f tmp_root ssh-copy-id root@$vm_compute1_ip_eth0"

#Check if succeeded
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ssh -o BatchMode=yes root@$vm_network_ip_eth0 'exit'"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ssh -o BatchMode=yes root@$vm_compute1_ip_eth0 'exit'"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"rm -f tmp_root"

ok
# Re run packstack
log "Running packstack with configured values - this may take a while.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"nohup packstack --answer-file=$ANSWERS_FILE" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum -y update" 

ok

# Reboot vms
log "Performing recommended reboot after packstack install.. "
virsh -c $kvm_uri reboot $vm_controller_name 
virsh -c $kvm_uri reboot $vm_network_name 
virsh -c $kvm_uri reboot $vm_compute1_name 
ok

# Wait for Domains to start - 30 seconds
log "Waiting 30 seconds for safe reboot.."
sleep 30
ok

## Create snapshots
log "Take snapshots of VMs after successful openstack install.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "ok_openstack_install" "Centos 7 Controller VM with fresh Neutron Openstack" \
--atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_network_name "ok_openstack_install" "Centos 7 Network VM with fresh Neutron Openstack" \
 --atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "ok_openstack_install" "Centos 7 Compute1 VM with fresh Neutron Openstack" \
--atomic --reuse-external 

ok

#4.b - OVS configuration on network-node

#log "Configure interface eth2 on the Network VM as a OVS-port.. "

#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"sudo truncate -s 0 /etc/sysconfig/network-scripts/ifcfg-eth2" 

#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DEVICE=\"eth2\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'ONBOOT=\"yes\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'TYPE=\"OVSPort\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DEVICETYPE=\"ovs\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'OVS_BRIDGE=br-ex' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'BOOTPROTO=\"none\"' | sudo tee --append /etc/sysconfig/network-scripts/ifcfg-eth2"
#ok

#log "Configure interface br-ex on the Network VM as a OVS-bridge.. "
#
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DEVICE=\"br-ex\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'BOOTPROTO=\"none\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'IPADDR=\"$vm_network_ip_eth2\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'NETMASK=\"$ext_network_netmask\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'GATEWAY=\"$ext_network_ip\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'TYPE=\"OVSIntPort\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'OVS_BRIDGE=\"br-ex\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DEVICETYPE=\"ovs\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DEFROUTE=\"yes\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"echo 'DNS1=\"$ext_network_ip\"' | tee --append /etc/sysconfig/network-scripts/ifcfg-br-ex"

#ok

# last: service network restart
#log "Restart the network service on the Network VM.. "
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_eth0 \
#"sudo service network restart"
#ok
#======================================================================
#
# 5. Install Rally and gather benchmarking data
#
#======================================================================

# Install Dependencies
log "Install Rally - dependencies.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum -y install gcc libffi-devel openssl-devel gmp-devel libxml2-devel libxslt-devel postgresql-devel git" 
ok
# Install Rally
log "Install Rally - download installation script.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"curl https://raw.githubusercontent.com/openstack/rally/master/install_rally.sh > ~/install_rally.sh && chmod +x ~/install_rally.sh" 
ok

log "Install Rally - run installation script - this may take a while.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo bash ~/install_rally.sh -y" 
ok

# Populate Rally's database
log "Populate Rally's database.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo rally-manage db recreate" 
ok

# Register Openstack in Rally
log "Register the Openstack deployment in Rally.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo -E bash -c 'source /root/keystonerc_admin; rally deployment create --fromenv --name=vorbe'" 
ok

# Use Deployment
log "Register the Openstack deployment in Rally.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"rally deployment use vorbe"
ok

# Deployment Check
log "Check that the current openstack deployment is healthy and ready to be benchmarked.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"rally deployment check" 
ok

# Run Tasks

## Create snapshots
log "Take snapshots of VMs after successful rally install.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "ok_rally_install" "Centos 7 Controller VM with fresh Neutron Openstack" \
--atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_network_name "ok_rally_install" "Centos 7 Network VM with fresh Neutron Openstack" \
 --atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "ok_rally_install" "Centos 7 Compute1 VM with fresh Neutron Openstack" \
--atomic --reuse-external 

ok

#======================================================================
#
# 6. Main Test Use case:
#    Configure external network, create image, boot instance and ssh into it
#
#======================================================================

# Add keystonerc file to bashrc so it is executed on every ssh call
log "Source the rc admin file - sets the required environment variables.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"echo 'source ~/keystonerc_$vm_user' >> .bashrc"
ok

# Create a cirros disk image with glance using online link resource
log "Create Cirros image from link.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"glance image-create \
--copy-from http://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img \
--is-public true \
--container-format bare \
--disk-format qcow2 \
--name cirros33"
ok

# Add a tinier flavor
log "Add nano image flavor to nova for test purposes.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"nova flavor-create m1.nano auto 128 1 1"
ok

# Ssh key for nova demo server 
log "Create keypair and add it to nova.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"ssh-keygen -t rsa -N \"\" -f id_rsa_demo; nova keypair-add --pub-key id_rsa_demo.pub demo"
ok

# Create security-groups
log "Create security-group default rules for icmp and ssh tcp traffic.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron security-group-rule-create --protocol icmp default; \
 neutron security-group-rule-create --protocol tcp --port-range-min 22 --port-range-max 22 default"
ok

# NETWORKING
# Create external network
log "Create the external network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron net-create external_network --router:external"
ok
# Subnet
log "Create external_subnet.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron subnet-create --name external_subnet --disable-dhcp external_network 172.16.16.0/24"
ok

# Router to external network
log "Create router to external_network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron router-create router_ext; neutron router-gateway-set router_ext external_network"
ok

# Create private network 
log "Create private network.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron net-create private_network 2>&1 | tee private-network.txt"

priv_net_id=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"cat private-network.txt | grep -o ' id .*' | tr -s ' ' | cut -f4 -d' '")

ok

# Create private subnet
log "Create private sub-network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron subnet-create --name private_subnet private_network 192.168.1.0/24"
ok

# Add router interface
log "Create private sub-network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"neutron router-interface-add router_ext private_subnet"
ok

# BOOT server
log "Boot the demo server with the previously defined configurations.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"nova boot --poll --flavor m1.nano --image cirros33 --nic net-id=$priv_net_id --key-name demo test_server"
ok

# Create a floating ip
log "Create a floating ip for inbound access to test_server.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"nova floating-ip-create external_network 2>&1 | tee test_server.floating-ip"

demo_floating_ip=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"cat test_server.floating-ip | grep -o '.* external_network' | cut -f4 -d' '")

ok

# Add floating ip to test a floating ip
log "Associate the floating ip with the test server instance.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"nova add-floating-ip test_server $demo_floating_ip"
ok

# Create a floating ip
#log ""
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
#""
#ok

log "Now we need to test if the test_server is reachable by its floating ip.. "
echo "[ ? ]"
