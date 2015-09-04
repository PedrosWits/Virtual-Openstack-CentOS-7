#!/bin/sh
#======================================================================
#
# INPUT ARGS
#
#======================================================================
# Usage
usage="Usage: install_orbit.sh [options]
   --clean [cfg-file] Clean installation (remove all traces). Parameters specified in cfg-file
   --save-base-vm     Save base vm - used for cloning any virtual node
   --skip-base-vm     Use a saved base vm - with name specified in vorbe.cfg
   --debug            Do not clean anything in case installation fails
   --help             Prompt usage and help information"

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
	CLEAN=1
	clean_cfg_file=$2
	shift
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
# Prog Name
#
#======================================================================
# Prog Name
prog_name="A Virtual Openstack RedHat-based Environment"
prog_sigla="orbit"

##======================================================================
#
# Set -e -u 
#
#======================================================================
# Set -e : Script exits on a command returning error
set -e
# Exit if trying to use an unset variable
set -u

##======================================================================
#
# Log Function and variables
#
#======================================================================

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

##======================================================================
#
# Function for user interaction
#
#======================================================================

# Function prompt yes no question
function promptyn {
  for j in 1 2 3; do
      read -t 10 -p "$1 [y/n]: " yn
      case $yn in
          [Yy]* ) return 0;;
          [Nn]* ) return 1;;
          * ) echo "Please answer y or n";;
      esac
  done
  return 1
}

##======================================================================
#
# Names of necessary files
#
#======================================================================
# Pointer to file loader script - takes the current path as argument
user_config="$(pwd -P)/orbit.conf"

##======================================================================
#
# If normal behavior - variables from user config
#
#======================================================================

if [ $CLEAN -eq 0 ]; then
    # Load user-defined variables
    log "Load variables from user-editable file - ${user_config}.. "
      source $user_config 
    ok
    # Save read config in new file with id specified in user_config
    save_config="$(pwd -P)/orbit.${config_id}"
    if [ -f $save_config ]; then
	log "File ${save_config} already exists. Please specify a different orbit-id in orbit.conf"; exit 1
    fi
    log "Save input configuration file in: ${save_config}.."
      touch $save_config
      cat $user_config > $save_config
    ok
    
   echo ""
   echo -e "$prog_sigla: $prog_name starting on $(date)" | tee --append $log_file
   echo -e "$log_tag #==================================================================#"
fi

##======================================================================
#
# Sanity check and Load functions
#
#======================================================================
log "Sanity check.. "

declare -a my_files=("scripts/reorder-ifaces.sh" "scripts/config-ovs-bridge.sh" "scripts/config-ovs-port.sh" "scripts/config-iface.sh" "scripts/set-ntp-dcc.sh" "templates/isolated-network.xml" "templates/nat-network.xml" "templates/orbit-centos7.ks" "functions/add-net-interface" "functions/clone-vm" "functions/delete-kvm-network" "functions/delete-vm" "functions/macgen-kvm" "functions/remove-net-interface")

for i in "${my_files[@]}"
do
  if [ ! -f "$(pwd -P)/$i" ]; then
    log "$SFAILED One of my files does not exist: $(pwd -P)/$i"; exit 1
  fi
done
ok

log "Load functions and templates.. "
 for f in $(pwd -P)/functions/*
   do source "$f"
 done

 xml_isolated_network="$(pwd -P)/templates/isolated-network.xml"
 xml_nat_network="$(pwd -P)/templates/nat-network.xml"
 template_kickstart="$(pwd -P)/templates/orbit-centos7.ks"

 script_iface="$(pwd -P)/scripts/config-iface.sh"
 script_ntp="$(pwd -P)/scripts/set-ntp-dcc.sh"
 script_ovs_bridge="$(pwd -P)/scripts/config-ovs-bridge.sh"
 script_ovs_port="$(pwd -P)/scripts/config-ovs-port.sh"
 script_reorder_ifaces="$(pwd -P)/scripts/reorder-ifaces.sh"
ok

##======================================================================
#
# Temporary xml files for virsh + kickstart file
# These serve as lock files (so that two orbit installs cannot
# occur at the same time)
#
#======================================================================

# Temporary files
data_network_file="$(pwd -P)/orbit_data_network.xml"
management_network_file="$(pwd -P)/orbit_management_network.xml"
external_network_file="$(pwd -P)/orbit_external_network.xml"

tmp_kickstart_file="kickstart.ks"

##======================================================================
#
# Cleanup function
#
#======================================================================

# Clean_up function - can only be defined after loading file names and user variables
function cleanup {
   if [ "$?" -eq 0 ]; then
      echo -e "$log_tag \e[0;32mInstallation successful!\e[0m" | tee --append $log_file   
   else
      set +e; set +u
      if [ $CLEAN -eq 1 ]; then
	 echo -e "$log_tag Cleaning up previous installation, with variables read from '$clean_cfg_file'.. " | tee --append $log_file
      else
	 echo -e "$SFAILED" | tee --append $log_file
	 echo -e "$log_tag \e[0;31mInstallation unsuccessful!\e[0m Cleaning up.." \
	   | tee --append $log_file
      fi
      if [ $DEBUG -eq 0 ] || [ $CLEAN -eq 1 ]; then
	     # Reset default-net, delete data-net.
	     if [ $checkpoint -ge 1 ]; then
		delete_net $data_network_name $kvm_uri
		delete_net $management_network_name $kvm_uri
		delete_net $ext_network_name $kvm_uri
	     fi
	     # Delete vms created
	     if [ $checkpoint -ge 2 ]; then
		if [ $SKIP_VM_CREATION -eq 0 ] && [ $SAVE_BASE_VM -eq 0 ]; then
		    delete_vm $vm_base_name $kvm_uri
		fi
		delete_vm $vm_controller_name $kvm_uri
		delete_vm $vm_network_name $kvm_uri
		delete_vm $vm_compute1_name $kvm_uri
	     fi
	     if [ $checkpoint -ge 3 ]; then
		# Clean known_hosts file		
		ssh-keygen -R $vm_controller_ip_ext
		ssh-keygen -R $vm_network_ip_ext
		ssh-keygen -R $vm_compute1_ip_ext
	     fi		
	     if [ $checkpoint -ge 4 ]; then
		# Clean known_hosts file		
		ssh-keygen -R $vm_controller_ip_man
		ssh-keygen -R $vm_network_ip_man
		ssh-keygen -R $vm_compute1_ip_man
	     fi   
	     ok
      fi
   fi

   if [ $CLEAN -eq 1 ]; then
     rm -f $clean_cfg_file
   else
     echo "checkpoint=$checkpoint" >> $save_config
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

##======================================================================
#
# Define signals to be caught and function to be run
#
#======================================================================

# Define trap
trap cleanup EXIT SIGHUP SIGINT SIGTERM SIGQUIT

##======================================================================
#
# If I was launched only to clean, then load previous config and exit
#
#======================================================================

if [ $CLEAN -eq 1 ]; then
  if [ ! -f ${clean_cfg_file} ]; then
     log "ERROR: ${clean_cfg_file} is not a valid configuration file."
     trap - EXIT SIGHUP SIGINT SIGTERM
     exit 1
  fi
    source $(pwd -P)/$clean_cfg_file
    set +u
    if [ -z $checkpoint ]; then
	checkpoint=100
    fi
    exit 1
fi

# DEBUG ONLY - UNCOMMENT BELOW FROM HERE TO
#RUN_ONLY_TEST_CASE=1

#if [ $RUN_ONLY_TEST_CASE -eq 0 ]; then

# DEBUG ONLY - HERE
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
mac_controller_management=$(gen_mac)
mac_controller_external=$(gen_mac)
mac_controller_dummy=$(gen_mac)
mac_network_management=$(gen_mac)
mac_network_data=$(gen_mac)
mac_network_external=$(gen_mac)
mac_compute1_management=$(gen_mac)
mac_compute1_data=$(gen_mac)
mac_compute1_dummy=$(gen_mac)
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
touch $data_network_file
touch $management_network_file
touch $external_network_file

cat $xml_isolated_network | tee --append $data_network_file
cat $xml_isolated_network | tee --append $management_network_file
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

#Data Network
## Edit the name
sed -i "s|<name>.*|<name>$data_network_name</name>|" $data_network_file
## Edit the bridge's name
sed -i "s|<bridge.*|<bridge name='$data_bridge_name'/>|" $data_network_file
## Edit the ip address
sed -i "s|<ip address.*|<ip address='$data_network_ip' netmask='$data_network_netmask'>|" $data_network_file

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
sed -i "/range start/a <host mac='$mac_network_external' name='$vm_network_name' ip='$vm_network_ip_ext'/>" $external_network_file
# Edit the ip for the controller node
sed -i "/range start/a <host mac='$mac_controller_external' name='$vm_controller_name' ip='$vm_controller_ip_ext'/>" $external_network_file
# Edit the ip for the compute1 node (just for initial configurations - then iface is removed)
sed -i "/range start/a <host mac='$mac_compute1_dummy' name='$vm_compute1_name' ip='$vm_compute1_ip_ext'/>" $external_network_file 
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
	create_vm $vm_base_name $vm_base_size $vm_base_ram $vm_base_vcpus $tmp_kickstart_file \
		  $kvm_uri $img_disk_path \
		  $management_network_name $(gen_mac) \
		  $data_network_name $(gen_mac) \
		  $ext_network_name $(gen_mac)	
        ok

	# Snapshot
	log "$vm_base_name - Create snapshot fresh install.. "
	virsh -c $kvm_uri snapshot-create-as $vm_base_name fresh_install "Centos 7 Base VM" \
	--atomic --reuse-external 
	ok

	# Prep Clone
	log "Prepare base VM for cloning - virt-sysprep.. "
	sudo virt-sysprep -c $kvm_uri -d $vm_base_name \
	--firstboot-command "echo 'HWADDR=' | cat - /sys/class/net/eth2/address | tr -d '\n' | sed 'a\' >> /etc/sysconfig/network-scripts/ifcfg-eth2"
	ok
fi


# Clone

## Into Controller
log "Cloning base vm into controller vm.. "
clone_vm $vm_base_name $vm_controller_name $mac_controller_management $mac_controller_dummy \
$mac_controller_external $kvm_uri $img_disk_path 
ok

## Into Network
log "Cloning base vm into network vm.. "
clone_vm $vm_base_name $vm_network_name $mac_network_management $mac_network_data \
$mac_network_external $kvm_uri $img_disk_path 
ok

## Into Compute1
log "Cloning base vm into compute1 vm.. "
clone_vm $vm_base_name $vm_compute1_name $mac_compute1_management $mac_compute1_data \
$mac_compute1_dummy $kvm_uri $img_disk_path 
ok

# Start Domains
log "Starting VMs - Write HWADDR in ifcfg-eth0 with first-boot.. "
virsh -c $kvm_uri start $vm_controller_name 
virsh -c $kvm_uri start $vm_network_name 
virsh -c $kvm_uri start $vm_compute1_name 
ok

# Wait for Domains to start - 10 seconds
log "Waiting 50 seconds for vms to start and perform first-boot script safely.."
sleep 50
ok

# Shutdown
log "Shutting down VMs for offline network configuration.. "
virsh -c $kvm_uri shutdown $vm_controller_name 
virsh -c $kvm_uri shutdown $vm_network_name 
virsh -c $kvm_uri shutdown $vm_compute1_name 
ok
#
log "Waiting 30 seconds for vms to shutdown safely.."
sleep 30
ok

# Start Domains
log "Re-starting the VMs.. "
virsh -c $kvm_uri start $vm_controller_name 
virsh -c $kvm_uri start $vm_network_name 
virsh -c $kvm_uri start $vm_compute1_name 
ok
#
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
  echo "" | tee --append $log_file
  log "A ssh key with the name '$ssh_key_name' already exists. Using the existing one.. "
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
	  1) hosti=$vm_controller_ip_ext;;
	  2) hosti=$vm_network_ip_ext;;
	  3) hosti=$vm_compute1_ip_ext;;
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
ssh-keyscan -t rsa,dsa $vm_controller_ip_ext >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_network_ip_ext >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_compute1_ip_ext >> ~/.ssh/known_hosts 
ok

# Set SSHPASS environment variable to use with sshpass
log "Set SSHPASS environment variable for non-interactive ssh-copy-id. Read pass from user.cfg.. "
export SSHPASS="$vm_pass"
ok

# Copy key into servers - use same key, no need for different keys - virtual environment thus this is
# the single point of access to it
log "Install the keys onto the VMs.. "
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_controller_ip_ext
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_network_ip_ext
sshpass -e ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_compute1_ip_ext
ok

# Find a way to test if this succedded - else we gotta exit cause we cant send commands to vms
# use timeout in ssh - if it fails then we gotta exit - delete all vms? 

log "Check if ssh-configuration was successfull.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_ext 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_ext 'exit' 
ok

# Configure eth1 on network and compute1 nodes
## On Network node
log "Configure interfaces. Controller node.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_ext \
"sudo bash -s" < $script_iface eth1 $mac_controller_external $vm_controller_ip_ext $ext_network_netmask $ext_network_ip $ext_network_ip
echo ""
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_ext \
"sudo bash -s" < $script_iface eth0 $mac_controller_management $vm_controller_ip_man $management_network_netmask
ok

log "Configure interfaces. Network node.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo bash -s" < $script_iface eth2 $mac_network_external $vm_network_ip_ext $ext_network_netmask $ext_network_ip $ext_network_ip
echo ""
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo bash -s" < $script_iface eth0 $mac_network_management $vm_network_ip_man $management_network_netmask
echo ""
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo bash -s" < $script_iface eth1 $mac_network_data $vm_network_ip_tun $data_network_netmask

ok

log "Configure interfaces. Compute1 node.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_ext \
"sudo bash -s" < $script_iface eth0 $mac_compute1_management $vm_compute1_ip_man $management_network_netmask $vm_network_ip_man $ext_network_ip
echo ""
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_ext \
"sudo bash -s" < $script_iface eth1 $mac_compute1_data $vm_compute1_ip_tun $data_network_netmask

ok

log "Configure iptables on the Network node.. "

# eth0 is the interface on the network node for the management network 
# eth2 is the interface on the network node for the external network
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I INPUT 5 -i eth0 -s $management_network_ip/$management_network_netmask -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 1 -i eth0 -o eth2 -s $management_network_ip/$management_network_netmask -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 2 -i eth2 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -t nat -I POSTROUTING 1 -o eth2 -j MASQUERADE"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo service iptables save"

# Enable Ipv4 forwarding - IMPORTANT!!
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"echo 'net.ipv4.ip_forward=1' | sudo tee --append /etc/sysctl.conf"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo sysctl -p /etc/sysctl.conf" 

ok

log "Set hostname resolution for openstack nodes.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_ext \
"echo -e \"$vm_controller_name $vm_controller_ip_man\n $vm_network_name $vm_network_ip_man\n $vm_compute1_name $vm_compute1_ip_man\" | sudo tee /etc/hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"echo -e \"$vm_controller_name $vm_controller_ip_man\n $vm_network_name $vm_network_ip_man\n $vm_compute1_name $vm_compute1_ip_man\" | sudo tee /etc/hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_ext \
"echo -e \"$vm_controller_name $vm_controller_ip_man\n $vm_network_name $vm_network_ip_man\n $vm_compute1_name $vm_compute1_ip_man\" | sudo tee /etc/hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_ext \
"sudo hostnamectl --static set-hostname $vm_controller_name"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo hostnamectl --static set-hostname $vm_network_name"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_ext \
"sudo hostnamectl --static set-hostname $vm_compute1_name"

ok

# Shutdown for offline config
log "Shutting down VMs for offline network configuration.. "
virsh -c $kvm_uri shutdown $vm_controller_name 
virsh -c $kvm_uri shutdown $vm_network_name 
virsh -c $kvm_uri shutdown $vm_compute1_name 
ok

# Wait for Domains to start - 10 seconds
log "Waiting 30 seconds for vms to shutdown safely.."
sleep 30
ok

## Remove NIC 1 from compute1 node - external
log "Remove external network interface from Compute1 node.. "
remove_interface $vm_compute1_name $mac_compute1_dummy $kvm_uri
remove_interface $vm_controller_name $mac_controller_dummy $kvm_uri
ok

# Start Domains
log "Re-starting the VMs.. "
virsh -c $kvm_uri start $vm_controller_name 
virsh -c $kvm_uri start $vm_network_name 
virsh -c $kvm_uri start $vm_compute1_name 
ok

# Wait for Domains to start - 50 seconds
log "Waiting 50 seconds for vms to start safely.."
sleep 50
ok

# Reconfigure known hosts for the Management network IPs
RESULT=0
log "Test if management-network Ips are available in the list of known_hosts.. "
  for i in 1 2 3; do
        case $i in
	  1) hosti=$vm_controller_ip_man;;
	  2) hosti=$vm_network_ip_man;;
	  3) hosti=$vm_compute1_ip_man;;
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
ok

checkpoint=4

log "Add VMs-management-ips to the list of known_hosts, by using key-scan.. "
ssh-keyscan -t rsa,dsa $vm_controller_ip_man >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_network_ip_man >> ~/.ssh/known_hosts 
ssh-keyscan -t rsa,dsa $vm_compute1_ip_man >> ~/.ssh/known_hosts 
ok

log "Check if ssh-configuration was successfull.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man 'exit' 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_man 'exit' 
ok
# Confirm that the VMs have internet connection and can ping each other

log "Verify that VMs have internet connection.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ping -c 2 www.google.com" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"ping -c 2 www.google.com" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_man \
"ping -c 2 www.google.com" 

ok

# Take Snapshots
log "Take snapshots of VMs after successful network configuration.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "net_config" "Centos 7 Controller VM" \
--atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_network_name "net_config" "Centos 7 Network VM" \
 --atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "net_config" "Centos 7 Compute1 VM" \
--atomic --reuse-external 

ok

# Configure ntp in openstack vms, controller - master, rest - slaves
##Controller
log "Configure and start the ntp service - Controller VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo bash -s" < $script_ntp 1

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
##Network
log "Configure and start the ntp service - Network VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"sudo bash -s" < $script_ntp 0 $vm_controller_ip_man

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
##Compute1
log "Configure and start the ntp service - Compute1 VM.."

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_man \
"sudo bash -s" < $script_ntp 0 $vm_controller_ip_man

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_compute1_ip_man \
"sudo systemctl enable ntpd.service && sudo systemctl start ntpd.service" 

ok
#======================================================================
#
# 4. Install Openstack
#
#======================================================================

# Rdo repository
log "Installing repository on Controller.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum install -q -y https://rdoproject.org/repos/rdo-release.rpm"

ok

# Install Packstack

log "Installing packstack.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum install -q -y openstack-packstack" 
# Openstack-Utils
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum install -q -y openstack-utils" 
# Yum update
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum -q -y update" 

ok


# Generate the answers-file with unix timestamp
ANSWERS_FILE="packstack_answers$(date +%s).conf"

log "Generate the answers file using packstack.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"packstack --gen-answer-file=$ANSWERS_FILE"

ok

# Edit answers file using openstack-config

log "Edit answers file according to our configuration: vms ips, ntp servers, etc.. "

#ssh -o BatchMode=yes $vm_user@$vm_controller_ip_man \
#"openstack-config --set $ANSWERS_FILE general CONFIG_SSH_KEY /home/$vm_user/.ssh/id_rsa.pub"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sed -i \"s|$vm_controller_ip_ext|$vm_controller_ip_man|\" $ANSWERS_FILE"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_COMPUTE_HOSTS $vm_compute1_ip_man"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NETWORK_HOSTS $vm_network_ip_man"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES gre"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TYPE_DRIVERS gre"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TUNNEL_ID_RANGES 1001:2000"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_VNI_RANGES 1001:2000"
#IMPORTANTE SENAO CONFIG DE REDE NAO FUNCIONA
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_BRIDGE_IFACES br-eth1:eth1"
# IMPORTANTE SENAO CONFIG DE REDE NAO FUNCIONA
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS physnet1:br-eth1"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_PROVISION_DEMO n"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_TUNNEL_IF eth1"

ok

# Install root ssh keys on root user from all nodes - so that packstack can perform priveledged
# installation on these nodes from the admin user in the controller node
log "Install ssh key in root users, for automating required priveleged packstack installation.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ssh-keyscan -t rsa,dsa $vm_network_ip_man >> ~/.ssh/known_hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ssh-keyscan -t rsa,dsa $vm_compute1_ip_man >> ~/.ssh/known_hosts"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo rpm -ivh http://pkgs.repoforge.org/sshpass/sshpass-1.05-1.el7.rf.x86_64.rpm"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"install -m 600 /dev/null tmp_root; echo $vm_root_pass > tmp_root"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo mkdir -p /root/.ssh/; cat ~/.ssh/id_rsa.pub | sudo tee --append /root/.ssh/authorized_keys"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sshpass -f tmp_root ssh-copy-id root@$vm_network_ip_man"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sshpass -f tmp_root ssh-copy-id root@$vm_compute1_ip_man"

#Check if succeeded
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ssh -o BatchMode=yes root@$vm_network_ip_man 'exit'"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ssh -o BatchMode=yes root@$vm_compute1_ip_man 'exit'"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"rm -f tmp_root"

ok
# Re run packstack
log "Running packstack with configured values - this may take a while.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nohup packstack --answer-file=$ANSWERS_FILE" 

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum -y update" 

ok

#OVS bridge configuration - network node - external network
log "OVS external bridge configuration through br-ex - fixing iptables accordingly.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"sudo bash -s" < ${script_ovs_bridge} br-ex ${vm_network_ip_ext} ${ext_network_netmask} ${ext_network_ip} ${ext_network_ip}

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"sudo bash -s" < ${script_ovs_port} eth2 br-ex

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 1 -i eth0 -o br-ex -s $management_network_ip/$management_network_netmask -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 2 -i br-ex -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -t nat -I POSTROUTING 1 -o br-ex -j MASQUERADE"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo service iptables save"

ok
# Reboot vms
log "Performing recommended reboot after packstack install.. "
virsh -c $kvm_uri reboot $vm_controller_name 
virsh -c $kvm_uri reboot $vm_network_name 
virsh -c $kvm_uri reboot $vm_compute1_name 
ok

# Wait for Domains to start - 30 seconds
log "Waiting 90 seconds for safe reboot.."
sleep 90
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

# DEBUG ONLY - UNCOMMENT LINE BELOW
# fi
checkpoint=5
#======================================================================
#
# 4b. Main Test Use case:
#    Create image, boot instance and ssh into it
#
#======================================================================

# Add keystonerc file to bashrc so it is executed on every ssh call
log "Source the rc admin file - sets the required environment variables.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo install -m 600 -o ${vm_user} -g ${vm_user} /root/keystonerc_${vm_user} /home/${vm_user}/; echo 'source ~/keystonerc_$vm_user' >> .bashrc"
ok

# Create a cirros disk image with glance using online link resource
log "Create Cirros image from link.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"glance image-create \
--copy-from http://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img \
--is-public true \
--container-format bare \
--disk-format qcow2 \
--name cirros33"
ok

# Add a tinier flavor
log "Add nano image flavor to nova for test purposes.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova flavor-create m1.nano auto 128 1 1"
ok

# Ssh key for nova demo server 
log "Create keypair and add it to nova.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"ssh-keygen -t rsa -N \"\" -f id_rsa_demo; nova keypair-add --pub-key id_rsa_demo.pub demo"
ok

# Create security-groups
log "Create security-group default rules for icmp and ssh tcp traffic.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron security-group-rule-create --protocol icmp default; \
 neutron security-group-rule-create --protocol tcp --port-range-min 22 --port-range-max 22 default"
ok

# NETWORKING
# Create external network
log "Create the external network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron net-create external_network --router:external"
ok
# Subnet
log "Create external_subnet.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron subnet-create --name external_subnet --disable-dhcp external_network $floating_network"
ok

# Router to external network
log "Create router to external_network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron router-create router_ext; neutron router-gateway-set router_ext external_network"
ok

# Create private network 
log "Create private network.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron net-create private_network 2>&1 | tee private-network.txt"

priv_net_id=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"cat private-network.txt | grep -o ' id .*' | tr -s ' ' | cut -f4 -d' '")

ok

# Create private subnet
log "Create private sub-network.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron subnet-create --name private_subnet private_network $test_tenant_network"
ok

# Add router interface
log "Add private subnet interface to router.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"neutron router-interface-add router_ext private_subnet"
ok

# BOOT server
log "Boot the demo server with the previously defined configurations.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova boot --poll --flavor m1.nano --image cirros33 --nic net-id=$priv_net_id --key-name demo test_server"
ok

# Get test server private ip number
log "Get the test server private ip.. "
test_private_ip=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova show test_server | grep private_network | tr -s ' ' | cut -f5 -d' '")
ok

# Reboot test_server
log "Reboot the test server.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova reboot test_server"
ok


# sleep? wait for instance to boot? while cycle? max-tries=3; sleep=60s
log "Retrieving network namespace.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"/usr/sbin/ip netns | grep dhcp | tee dhcp_namespace.txt"

dhcp_namespace=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man "cat dhcp_namespace.txt")

ok

log "Waiting for test instance to boot. Ping instace through network namespace to test correct configuration and availability.. "
for i in 1 2 3; do
  echo "Sleeping for 60 seconds"
  sleep 60
  echo "Pinging instance.. "
  ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
  "sudo /usr/sbin/ip netns exec ${dhcp_namespace} ping -c 4 $test_private_ip" && break || true && echo "Failed, trying again..";
done
ok

# Create a floating ip
log "Create a floating ip for inbound access to test_server.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova floating-ip-create external_network 2>&1 | tee test_server.floating-ip"
demo_floating_ip=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"cat test_server.floating-ip | grep -o '.* external_network' | cut -f4 -d' '")
ok

# Add floating ip to test a floating ip
log "Associate the floating ip with the test server instance.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"nova add-floating-ip test_server $demo_floating_ip"
ok

# Add ip addr   
log "Configure network node to allow external traffic coming from and into the instance.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
"sudo /usr/sbin/ip addr add $floating_network dev br-ex"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 1 -s $floating_network -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -I FORWARD 1 -d $floating_network -j ACCEPT"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo iptables -t nat -I POSTROUTING 1 -s $floating_network -j MASQUERADE"
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_ext \
"sudo service iptables save"

ok

# Final couple of tests: icmp + ssh
log "Check if the test server is reachable by its floating ip: with icmp.. "
  ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
  "ping -c 4 $demo_floating_ip"
ok

log "Check if the test server is reachable by its floating ip: with ssh.. "
 private_demo_key=$(ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
 "cat ~/id_rsa_demo")
 ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
 "echo \"$private_demo_key\" > ~/id_rsa_demo; chmod 600 ~/id_rsa_demo"
 ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
 "ssh-keyscan -t rsa,dsa $demo_floating_ip >> ~/.ssh/known_hosts"
 ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
 "ssh -i ~/id_rsa_demo cirros@$demo_floating_ip \"echo Im alive at last - cirros instance\""
 ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_network_ip_man \
 "ssh -i ~/id_rsa_demo cirros@$demo_floating_ip \"echo Can I ping google?; ping -c 4 8.8.8.8\""

ok

## Create snapshots
log "Take snapshots of VMs after successful Openstack testing.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "ok_basic_test" "Centos 7 Controller VM successful configuration / basic test case" \
--atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_network_name "ok_basic_test" "Centos 7 Network VM successful configuration/ basic test case" \
 --atomic --reuse-external 

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "ok_basic_test" "Centos 7 Compute1 VM successful configuration / basic test case" \
--atomic --reuse-external 

ok

checkpoint=6

#======================================================================
#
# 5. Install Rally and gather benchmarking data
#
#======================================================================

# Install Dependencies
log "Install Rally - dependencies.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo yum -y install gcc libffi-devel openssl-devel gmp-devel libxml2-devel libxslt-devel postgresql-devel git python-pip"  
ok
# Install Rally
log "Install Rally - download installation script.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"curl https://raw.githubusercontent.com/openstack/rally/master/install_rally.sh > ~/install_rally.sh && chmod +x ~/install_rally.sh" 
ok

# Install ez_setup.py to fix a rally installation problem based on pip egg
log "Fix a problem with Rally installation script.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"curl https://bitbucket.org/pypa/setuptools/raw/bootstrap/ez_setup.py > ~/ez_setup.py && chmod +x ~/ez_setup.py" 
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo python ~/ez_setup.py" 
ok

log "Install Rally - run installation script - this may take a while.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo bash ~/install_rally.sh -y" 
ok

# Populate Rally's database
log "Populate Rally's database.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo rally-manage db recreate" 
ok

# Register Openstack in Rally
log "Register the Openstack deployment in Rally.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"sudo -E bash -c 'source /root/keystonerc_admin; rally deployment create --fromenv --name=orbit'" 
ok

# Use Deployment
log "Register the Openstack deployment in Rally.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
"rally deployment use orbit"
ok

# Deployment Check
log "Check that the current openstack deployment is healthy and ready to be benchmarked.. "
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_man \
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
checkpoint=7
