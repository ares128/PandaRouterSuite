

function check_wan_config(){
	local wan=${1}
	local type=$(uci -p /var/state get network.${wan}.type 2> /dev/null) 
	if [ -z "${type}" ]; then
		echo "Interface ${wan} is not exists or not in bridge mode" && exit 1
	fi

	local metric=$(uci -p /var/state get network.${wan}.metric 2> /dev/null) 
	if [ -z "${metric}" ]; then
		echo "Interface ${wan} did not set a metric" && exit 1
	fi
	
}

function _count_wan(){
	global_wan_count=$((global_wan_count+1))
}

function count_wan(){
	global_wan_count=0
	config_load panda
	config_foreach _count_wan wan
	echo ${global_wan_count}
}

function rule_to_ipt(){
	local var=$1
	local section=$2
	
	local proto src_ip src_port dest_ip dest_port comment

	config_get proto ${section} proto
	config_get src_ip ${section} src_ip
	config_get src_port ${section} src_port
	config_get dest_ip ${section} dest_ip
	config_get dest_port ${section} dest_port
	config_get comment ${section} comment
	

	case ${proto} in
		tcp|udp)
			append "$var" " -p ${proto}"
			if [ -n "${src_port}" ] ; then append "$var" " -m multiport --sports ${src_port}" ; fi
			if [ -n "${dest_port}" ] ; then append "$var" " -m multiport --dports ${dest_port}" ; fi 
		;;
		""|all)
		;;
		*)
			append "$var" " -p ${proto}"
		;;
	esac
	
	if [ -n "${src_ip}" ] ; then append "$var" " -s ${src_ip}" ; fi
	if [ -n "${dest_ip}" ] ; then append "$var" " -d ${dest_ip}" ; fi
	if [ -n "${comment}" ] ; then append "$var" " -m comment --comment \"${comment}\"" ; fi
}
