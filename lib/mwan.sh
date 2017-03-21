

function _mwan_create_ipt_rule_rule(){
	local rule=$1
	local str=""
	rule_to_ipt str ${rule}
	
	local policy
	config_get policy ${rule} policy
	
	if [ -n ${policy} ] ; then
		echo "iptables -A Panda_mwan_rule -t mangle -m mark --mark 0/0xf ${str} -j Panda_mwan_policy_${policy}" 
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

	echo "iptables -A Panda_mwan_rule -t mangle -m mark --mark 0/0xf -j Panda_mwan_policy_balanced"
}

function _mwan_create_ipt_policy_iter_1(){
	wan=$1
	max_wan=$((max_wan+1))
	echo "iptables -N Panda_mwan_policy_${wan} -t mangle"
	printf "iptables -A Panda_mwan_policy_%s -t mangle -m mark --mark 0x0/0xf -j MARK --set-mark 0x%x/0xf\n" ${wan} ${max_wan}
	local upload download
	config_get upload ${wan} upload
	config_get download ${wan} download
	up_down_total=$((up_down_total+upload+download))


	
}
function _mwan_create_ipt_policy_iter_2(){
	wan=$1
	current_wan=$((current_wan+1))

	if [ ${current_wan} -eq ${max_wan} ] ; then
		printf "iptables -A Panda_mwan_policy_balanced -t mangle -m mark --mark 0/0xf -j MARK --set-mark 0x%x/0xf\n" ${current_wan}
	else
		local upload download
		config_get upload ${wan} upload
		config_get download ${wan} download
		local selfspeed=$((upload+download))
		local percentage=$((selfspeed*1000/up_down_total))
		printf "iptables -A Panda_mwan_policy_balanced -t mangle -m mark --mark 0/0xf -m statistic --mode random --probability 0.%03d -j MARK --set-mark 0x%x/0xf\n" ${percentage} ${current_wan}
		up_down_total=$((up_down_total-selfspeed))
	fi
}

function _mwan_create_ipt_policy(){
	up_down_total=0
	max_wan=0
	config_load panda
	config_foreach _mwan_create_ipt_policy_iter_1 wan
	
	echo "iptables -N Panda_mwan_policy_balanced -t mangle"
	current_wan=0
	config_foreach _mwan_create_ipt_policy_iter_2 wan
}

function _mwan_create_ipt(){
	_mwan_create_ipt_policy
	
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

function _mwan_remove_ipt_policy_wan(){
	wan=$1
	echo "iptables -F Panda_mwan_policy_${wan} -t mangle"
	echo "iptables -X Panda_mwan_policy_${wan} -t mangle"

	echo "iptables -F Panda_mwan_in_${wan} -t mangle"
	echo "iptables -X Panda_mwan_in_${wan} -t mangle"
}

function _mwan_remove_ipt_policy(){

	config_load panda
	config_foreach _mwan_remove_ipt_policy_wan wan

	echo "iptables -F Panda_mwan_policy_balanced -t mangle"
	echo "iptables -X Panda_mwan_policy_balanced -t mangle"
}

function _mwan_remove_ipt_rule(){
	echo "iptables -F Panda_mwan_rule -t mangle"
	echo "iptables -X Panda_mwan_rule -t mangle"
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
