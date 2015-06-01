#!/bin/sh
#======================================================================
#
# 0. Startup
#
#======================================================================
# Input args
SKIP_VM_CREATION=1
VERBOSE=1

if [ $VERBOSE -eq 1 ]; then
  verb=""
else 
  verb="&> /dev/null"
fi

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

# Pointer to file loader script - takes the current path as argument
config_files="src/config/file-tree.sh"
user_config="$PWD/user.cfg"

echo ""
log "$prog_name starting on $(date).\n"
echo -e "$log_tag #==================================================================#"
# Load user-defined variables
log "Load variables from user-editable file - $user_config.. "
source $user_config
ok

# Load file names
log "Load file names and structure.. "
source $config_files $(pwd -P)
ok

data_network_file="$(pwd -P)/openstack_data_network.xml"
# Clean_up function - can only be defined after loading file names and user variables
function cleanup {
   if [ "$?" -eq 0 ]; then
   	   echo -e -n "\n$log_tag \e[0;32mInstallation successful!\e[0m\n"
   else
     	   echo -e -n "$SFAILED\n"
	   echo -e -n "\n$log_tag \e[0;31mInstallation unsuccessful!\e[0m Cleaning up..\n"
	   # Reset default-net, delete data-net.
	   if [ $checkpoint -ge 1 ]; then
		    rm -f $data_network_file
                    source $manage_vms_reset_default $kvm_uri
                    source $manage_vms_delete_net $data_network_name $kvm_uri
	   fi
	   # Delete vms created
	   if [ $checkpoint -ge 2 ]; then
		    if [ $SKIP_VM_CREATION -eq 0 ]; then
		    	source $manage_vms_delete_vm $vm_base_name $kvm_uri
		    fi
		    source $manage_vms_delete_vm $vm_controller_name $kvm_uri
                    source $manage_vms_delete_vm $vm_network_name $kvm_uri
                    source $manage_vms_delete_vm $vm_compute1_name $kvm_uri
		    # Clean libvirt leases file for default network		    
		    sudo truncate -s0 /var/lib/libvirt/dnsmasq/default.leases
		    sudo truncate -s0 /var/lib/libvirt/dnsmasq/virbr0.status
		
   	   fi
	  # if [ $checkpoint -ge 3 ]; then
	  # 	    # Clean known_hosts file
	  # fi
   fi
   # Line on stdout
   echo ""
}
# Define trap
trap cleanup EXIT SIGHUP SIGINT SIGTERM

#=====================================================================
#
# 1. Libvirt
#
#======================================================================
checkpoint=1

# Generate MACS and constants
log "Generate MACs.. "
source $config_constants $utility_macgen
ok

log "Check if required software is installed.. "



ok

# Create data network in libvirt
# if given network exists exit
RESULT=0

log "Test if name '$data_network_name' for data network is available.. "
virsh -c $kvm_uri net-info $data_network_name &> /dev/null && RESULT=1 || true 
if [ $RESULT -eq 1 ]; then
  exit 1
fi
ok

log "Creating temporary file $data_network_file, for creating data network through xml template.. "
touch $data_network_file
cat $xml_data_network | tee --append $data_network_file
ok

log "Prepare xml file for creating isolated data network .. "

## Edit the name
sed -i "s|<name>.*|<name>$data_network_name</name>|" $data_network_file
## Edit the bridge's name
sed -i "s|<bridge.*|<bridge name='$data_bridge_name'/>|" $data_network_file
## Edit the ip address
sed -i "s|<ip address.*|<ip address='$data_network_ip' netmask='255.255.255.0'>|" $data_network_file
## Edit the dhcp range start-end
sed -i "s|<range.*|<range start='$data_network_ip_start' end='$data_network_ip_end'/>|" $data_network_file
## Edit the ip for network node
sed -i "/range start/a <host mac='$mac_network_data' name='$vm_network_name' ip='$vm_network_ip_eth1'/>" $data_network_file
## Edit the ip for the compute1 node
sed -i "/range start/a <host mac='$mac_compute1_data' name='$vm_compute1_name' ip='$vm_compute1_ip_eth1'/>" $data_network_file

ok

## Create and start the network
log "Create and start the network $data_network_name.. "
virsh -c $kvm_uri net-define $data_network_file
virsh -c $kvm_uri net-start $data_network_name
virsh -c $kvm_uri net-autostart $data_network_name
ok

# Check if ips are available in net-default through net-dumpxml
log "Check if the requested IPs are available for the default network.. "
virsh -c $kvm_uri net-dumpxml default | grep -w -v -q "$vm_controller_ip_eth0\|$vm_network_ip_eth0\|$vm_compute1_ip_eth0"
ok

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
EDITOR="sed -i \"/<dhcp>/a <host mac = '$mac_compute1_default' name='$vm_compute1_name' ip='$vm_compute1_ip_eth0'/>\"" virsh -c $kvm_uri net-edit default
ok

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
if [ $SKIP_VM_CREATION -eq 0 ]; then
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
fi


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
log "Adding network-interfaces for $network_data_name network in network and compute1 nodes.."
## Add NIC 2 to network node
source $virt_add_nic $vm_network_name $data_network_name $mac_network_data $kvm_uri
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

# Now I can run commands remotely on the VMs using ssh
# Setup ssh keys so we can run commands over ssh without prompting for password
##  Do not create it if it exists already

log "Generate ssh key for accessing the VMs automatically.. "
if [ -f ~/.ssh/$ssh_key_name ]; then
  log "A ssh key with the name '$ssh_key_name' already exists. Using the existing one.. "
else
  ssh-keygen -t rsa -N "" -f $ssh_key_name
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
	     echo ""
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

# Copy key into servers - use same key, no need for different keys - virtual environment thus this is
# the single point of access to it
# Keys for root access
log "Install the keys onto the VMs.. "
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_controller_ip_eth0
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_network_ip_eth0
ssh-copy-id -i ~/.ssh/$ssh_key_name.pub $vm_user@$vm_compute1_ip_eth0
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
## If something fails from now on - just revert-snapshots to fresh_clone
checkpoint=-4

# Rdo repository
log "Installing packstack on the Controller VM.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y https://rdoproject.org/repos/rdo-release.rpm"
# Install Packstack
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y openstack-packstack"
# Openstack-Utils
ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"sudo yum install -y openstack-utils"
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
#"openstack-config --set $ANSWERS_FILE general CONFIG_NTP_SERVERS $ntp_servers_list"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_COMPUTE_HOSTS $vm_compute1_ip_eth0"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NETWORK_HOSTS $vm_network_ip_eth0"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_TUNNEL_ID_RANGES 1001:2000"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_VXLAN_GROUP 239.1.1.2"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_ML2_VNI_RANGES 1001:2000"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS physnet1:br-ex"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_PROVISION_DEMO n"

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"openstack-config --set $ANSWERS_FILE general CONFIG_NEUTRON_OVS_TUNNEL_IF eth1"

ok

# Re run packstack
log "Running packstack with configured values - this may take a while.. "

ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \
"packstack --answer-file=$name_packstack_file"

ok

## Create snapshots
log "Take snapshots of VMs after successful openstack install.. "

virsh -c $kvm_uri snapshot-create-as $vm_controller_name "ok_openstack_install" "Centos 7 Controller VM with fresh Neutron Openstack" \
--atomic --reuse-external

virsh -c $kvm_uri snapshot-create-as $vm_network_name "ok_openstack_install" "Centos 7 Network VM with fresh Neutron Openstack" \
 --atomic --reuse-external

virsh -c $kvm_uri snapshot-create-as $vm_compute1_name "ok_openstack install" "Centos 7 Compute1 VM with fresh Neutron Openstack" \
--atomic --reuse-external

ok

#======================================================================
#
# 5. Install Rally and gather benchmarking data
#
#======================================================================
# If something fails- revert snapshots
checkpoint=-5

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
"sudo -E bash -c 'source /root/keystonerc_admin; rally deployment create --fromenv --name=existing'"
ok

# Show results
#ssh -i ~/.ssh/$ssh_key_name -o BatchMode=yes $vm_user@$vm_controller_ip_eth0 \

