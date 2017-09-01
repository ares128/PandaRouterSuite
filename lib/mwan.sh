function _split_wan_and_sort(){
    OLDIFS=$IFS
	IFS=" ;,"
	for item in $1
	do
		echo ${item}
	done | sort
	IFS=$OLDIFS
}

function _concat_wan(){
    declare -a arr=("${!1}")
    for item in ${arr[@]}; do
        printf "_%s" $item
    done
}

function chain_exists(){
    [ $# -lt 1 -o $# -gt 2 ] && { 
        echo "Usage: chain_exists <chain_name> [table]" >&2
        return 1
    }
    local chain_name="$1" ; shift
    [ $# -eq 1 ] && local table="--table $1"
    iptables $table -n --list "$chain_name" >/dev/null 2>&1
}

function _mwan_check_index_iter(){
	wan=$1
	to_wan=$2
	wan_index=$((wan_index+1))
	if [[ ${wan} == ${to_wan} ]] ; then
		ret_index=$wan_index
		return 1
	fi

}

function _mwan_check_index(){
	wan_name=$1

	ret_index=0
	wan_index=0

	config_foreach _mwan_check_index_iter wan ${wan_name}

	echo ${ret_index}
}


function _mwan_create_policy_arr(){
	name=$1
	declare -a arr=("${!2}")

	echo "iptables -N Pmp${name} -t mangle"	

	up_down_total=0
	current_index=0
	length_wan=0

	for wan in ${arr[@]}; do
		local upload download
		config_get upload ${wan} upload
		config_get download ${wan} download
		up_down_total=$((up_down_total+upload+download))
		length_wan=$((length_wan+1))
	done

	for wan in ${arr[@]}; do
		current_index=$((current_index+1))
		wan_index=$(_mwan_check_index $wan)

		if [ ${current_index} -eq ${length_wan} ] ; then
			printf "iptables -A Pmp${name} -t mangle -m mark --mark 0/0xf -j MARK --set-mark 0x%x/0xf\n" ${wan_index}		
		else
			local upload download
			config_get upload ${wan} upload
			config_get download ${wan} download
			local selfspeed=$((upload+download))
			local percentage=$((selfspeed*1000/up_down_total))
			printf "iptables -A Pmp${name} -t mangle -m mark --mark 0/0xf -m statistic --mode random --probability 0.%03d -j MARK --set-mark 0x%x/0xf\n" ${percentage} ${wan_index}
			up_down_total=$((up_down_total-selfspeed))			
		fi

		
 
	done

}

function _mwan_create_ipt_rule_rule(){
	local rule=$1
	local str=""
	rule_to_ipt str ${rule}
	
	local policy
	config_get policy ${rule} policy
	
	if [ -n ${policy} ] ; then
		policyarr=$(_split_wan_and_sort ${policy})

		policy_name=$(_concat_wan policyarr[@])

		#not exist policy
		chain_exists Pmp${policy_name} mangle
		if [ $? -ne 0 ]; then
			_mwan_create_policy_arr ${policy_name} policyarr[@]
		fi
		
		echo "iptables -A Panda_mwan_rule -t mangle -m mark --mark 0/0xf ${str} -j Pmp${policy_name}" 
	fi
	
}

function _mwan_create_ipt_rule_wan(){
	wan=$1
	wan_index=$((wan_index+1))

	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	echo "iptables -N Panda_mwan_in_${wan} -t mangle"
	#echo "iptables -A Panda_mwan_in_${wan} -t mangle -i ${brstr} -m set --match-set mwan_direct src -m mark --mark 0/0xf -j MARK --set-mark 0xf/0xf"
	echo "iptables -A Panda_mwan_in_${wan} -t mangle -i ${brstr} -m mark --mark 0/0xf -j MARK --set-mark ${wan_index}/0xf"

	echo "iptables -A Panda_mwan_rule -t mangle -j Panda_mwan_in_${wan}"


}

function _mwan_create_ipt_rule(){
	
	echo "iptables -N Panda_mwan_rule -t mangle"

	config_load panda
	wan_index=0
	config_foreach _mwan_create_ipt_rule_wan wan
	echo "iptables -A Panda_mwan_rule -t mangle -m mark --mark 0/0xf -m set --match-set mwan_direct dst -j MARK --set-mark 0xf/0xf"
	config_foreach _mwan_create_ipt_rule_rule rule

	echo "iptables -A Panda_mwan_rule -t mangle -m mark --mark 0/0xf -j Pmp_balanced"
}

function _mwan_create_ipt_policy_balanced_1(){
	wan=$1
	max_wan=$((max_wan+1))
	local upload download
	config_get upload ${wan} upload
	config_get download ${wan} download
	up_down_total=$((up_down_total+upload+download))


	
}
function _mwan_create_ipt_policy_balanced_2(){
	wan=$1
	current_wan=$((current_wan+1))

	if [ ${current_wan} -eq ${max_wan} ] ; then
		printf "iptables -A Pmp_balanced -t mangle -m mark --mark 0/0xf -j MARK --set-mark 0x%x/0xf\n" ${current_wan}
	else
		local upload download
		config_get upload ${wan} upload
		config_get download ${wan} download
		local selfspeed=$((upload+download))
		local percentage=$((selfspeed*1000/up_down_total))
		printf "iptables -A Pmp_balanced -t mangle -m mark --mark 0/0xf -m statistic --mode random --probability 0.%03d -j MARK --set-mark 0x%x/0xf\n" ${percentage} ${current_wan}
		up_down_total=$((up_down_total-selfspeed))
	fi
}

function _mwan_create_ipt_balanced(){
	up_down_total=0
	max_wan=0
	config_load panda
	config_foreach _mwan_create_ipt_policy_balanced_1 wan
	
	echo "iptables -N Pmp_balanced -t mangle"
	current_wan=0
	config_foreach _mwan_create_ipt_policy_balanced_2 wan
}

function _mwan_create_ipt(){
	_mwan_create_ipt_balanced
	
	echo "iptables -N Panda_mwan -t mangle"
	echo "iptables -A Panda_mwan -t mangle -j CONNMARK --restore-mark --mask 0xf"
	_mwan_create_ipt_rule

	echo "iptables -A Panda_mwan -t mangle -j Panda_mwan_rule -m mark --mark 0x0/0xf"
	echo "iptables -A Panda_mwan -t mangle -j CONNMARK --save-mark --mask 0xf"
}

function _mwan_create_ipset(){
	
	echo "ipset -! create mwan_direct hash:net"
	
	for ip in $(ip route | awk '{print $1}' | egrep '(25[0-5]|2[0-4][0-9]|[1]?[1-9][0-9]?){3}(\.(25[0-5]|2[0-4][0-9]|[1]?[1-9]?[0-9]))') ; do
		echo "ipset -! add mwan_direct ${ip}"
	done

	for ip in $(ip route list table 0 | awk '{print $2}' | egrep '(25[0-5]|2[0-4][0-9]|[1]?[1-9][0-9]?){3}(\.(25[0-5]|2[0-4][0-9]|[1]?[1-9]?[0-9]))') ; do
		echo "ipset -! add mwan_direct ${ip}"
	done
	
	echo "ipset -! add mwan_direct 224.0.0.0/3"
}

function _mwan_remove_ipset(){
	echo "ipset -! destroy mwan_direct"
}

function _mwan_remove_ipt_rule_rule(){
	local rule=$1
	local str=""
	rule_to_ipt str ${rule}
	
	local policy
	config_get policy ${rule} policy
	
	if [ -n ${policy} ] ; then
		policyarr=$(_split_wan_and_sort ${policy})

		policy_name=$(_concat_wan policyarr[@])

		#not exist policy
		chain_exists Pmp${policy_name} mangle
		if [ $? -eq 0 ]; then
			echo "iptables -F Pmp${policy_name} -t mangle"
			echo "iptables -X Pmp${policy_name} -t mangle"
		fi
		
	fi
}

function _mwan_remove_ipt_policy_wan(){
	wan=$1

	echo "iptables -F Panda_mwan_in_${wan} -t mangle"
	echo "iptables -X Panda_mwan_in_${wan} -t mangle"
}



function _mwan_remove_ipt_policy(){

	config_load panda
	config_foreach _mwan_remove_ipt_policy_wan wan

	echo "iptables -F Pmp_balanced -t mangle"
	echo "iptables -X Pmp_balanced -t mangle"
}

function _mwan_remove_ipt_rule(){
	echo "iptables -F Panda_mwan_rule -t mangle"
	echo "iptables -X Panda_mwan_rule -t mangle"

	config_load panda

	config_foreach _mwan_remove_ipt_rule_rule rule
}


function _mwan_remove_ipt(){
	echo "iptables -F Panda_mwan -t mangle"
	echo "iptables -X Panda_mwan -t mangle"
	_mwan_remove_ipt_rule
	_mwan_remove_ipt_policy
}

function _mwan_create_route_iter(){
	local wan=$1
	mwan_index=$((mwan_index+1))
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local metric=$(uci -p /var/state get network.${wan}.metric 2> /dev/null)
	local ip=$(uci -p /var/state get network.${wan}.ipaddr 2> /dev/null)
	local mask=$(uci -p /var/state get network.${wan}.netmask 2> /dev/null)

	local route_gw
	
	network_get_gateway route_gw ${wan}
	
	echo "ip route add table ${mwan_index} default via ${route_gw} dev ${brstr}"

	echo "ip rule add pref $((mwan_index+1000)) iif ${brstr} lookup main"
	echo "ip rule add pref $((mwan_index+2000)) fwmark ${mwan_index}/0xf lookup ${mwan_index}"


}


function _mwan_create_route(){
	mwan_index=0
	config_load panda
	config_foreach _mwan_create_route_iter wan
}

function _mwan_remove_route_iter(){
	local wan=$1
	mwan_index=$((mwan_index+1))
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local metric=$(uci -p /var/state get network.${wan}.metric 2> /dev/null)
	local ip=$(uci -p /var/state get network.${wan}.ipaddr 2> /dev/null)
	local mask=$(uci -p /var/state get network.${wan}.netmask 2> /dev/null)

	echo "ip rule del pref $((mwan_index+1000))"
	echo "ip rule del pref $((mwan_index+2000))"

	echo "ip route flush table ${mwan_index}"
}

function _mwan_remove_route(){
	mwan_index=0
	config_load panda
	config_foreach _mwan_remove_route_iter wan
}

function mwan_create(){
	_mwan_create_ipset
	_mwan_create_ipt
	_mwan_create_route
}

function mwan_remove(){
	
	_mwan_remove_ipt
	_mwan_remove_route
	_mwan_remove_ipset
}
