#!/bin/sh
# 
#--------------------------------------------#
#
# Log Setup using Input $1 - Log file
#		  Input $2 - Color
#--------------------------------------------#
log_file=$1
color=$2

# requires load-color.sh
case "$color" in
	"y") COLOR=$BYellow
	;;
	"c") COLOR=$BCyan
	;;
	"r") COLOR=$BRed
	;;
	"b") COLOR=$BBlue
	;;
	"w") COLOR=$BWhite
	;;
	"g") COLOR=$BGreen
	;;
	"k") COLOR=$BBlack
	;;
	*) echo "Given color not available: $color"
	   exit 1
	;;
esac

# Constant: Number of Lines retained in Log file
retain_num=0

logsetup() {
	log_tag="$COLOR[Centos7 Virtual Openstack]$Color_Off"
	
	# Create Log File
	#TMP=$(tail -n $retain_num $log_file 2>/dev/null) && echo "${TMP}" > $log_file
	#exec > >(tee -a $log_file)
	#exec 2>&1
}

log() {
	echo -e "$log_tag $*"
}

