#==============================================================================+
# Kickstart for vm in openstack environment w/ centos7
#==============================================================================+

# text mode (no graphical mode)
text

# do not configure X
skipx

# non-interactive command line mode
cmdline

# install
install

# install from online url
url --url=http://centos.mirror.iweb.ca/7/os/x86_64/

# Language support
lang en_GB

# keyboard
keyboard pt-latin1

# network
network --onboot=on --bootproto=dhcp

# root password - naoseiroot
rootpw --iscrypted $1$HZjHOJI2$fr0FABA5RbV5.lPkhcBDC.

# firewall
firewall --service=ssh

# auth config
auth --useshadow --enablemd5

# SElinux
selinux --disabled

# timezone
timezone --utc UTC

# bootloader
bootloader --location=mbr

# clear the MBR (Master Boot Record)
zerombr

# Eula agreed
eula --agreed

# Services
services --enabled=sshd
services --disabled=NetworkManager

# the Setup Agent is not started the first time the system boots
firstboot --disable

# power off after installation
poweroff

################################################################################
# LVM partitions

bootloader --location=mbr
# do not remove any partition (preserve the gpt label)
clearpart --all --initlabel

# from: https://www.centosblog.com/centos-7-minimal-kickstart-file/
part swap --asprimary --fstype="swap" --size=1024
part /boot --fstype xfs --size=200
part pv.01 --size=1 --grow
volgroup rootvg01 pv.01
logvol / --fstype xfs --name=lv01 --vgname=rootvg01 --size=1 --grow

####
#Users

#user admin -> pw = admin123
user --name=admin --groups=admin,wheel --password=$1$5qdn/3le$TJI2V/LVB8pKsTZbxkcGH/ --iscrypted

#user demo -> pw = demo123
user --name=demo --groups=demo,users --password=$1$Aq5JWz6a$dO5RRkXSLrf5ZVTiJYCkH1 --iscrypted

################################################################################
# Packages

%packages –nobase
@core
policycoreutils
tree
wget
vim
aide
net-tools
ntp
%end
################################################################################

%post
# cleanup the installation
yum clean all
# create default ssh keys
ssh-keygen -q -t rsa -N "" -f /root/.ssh/id_rsa
# create default authorized_keys file
cp -p -f --context=system_u:object_r:ssh_home_t:s0 /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
# do not permit root login over ssh
#/bin/sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# run Aide to generate initial database
aide -i
# Disable NetworkManager and start network service instead
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl enable network
systemctl start network
# Update packages
yum update -y
%end

################################################################################
