function record_has_ip(){
	local ip=$1
	if [ -e /var/run/panda ] ; then
		if sed '1d' /var/run/panda | awk '{print $1}' | grep -Fxq ${ip} ; then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
	
}


function current_time(){
	awk '{printf "%d",$1*1000}' /proc/uptime
}

function record_add_ip(){
	local ip=$1
	local cindex=0
	if [ -e /var/run/panda ] ; then
		cindex=$(cat /var/run/panda | wc -l)
	fi

	if [ ${cindex} -eq "0" ]; then
		echo "echo $(current_time) > /var/run/panda"
		echo "echo \"${ip} 0 0 0 0\">> /var/run/panda"
		create_ip 1 ${ip}

	else
		echo "echo \"${ip} 0 0 0 0\">> /var/run/panda"
		create_ip $((cindex)) ${ip} 
	fi

}



function update_bw(){
	local tempi=$(mktemp)
	local tempo=$(mktemp)
	local templast=$(mktemp)
	
	local ltime=$(sed -n '1p' /var/run/panda)
	local ctime=$(current_time)
	local span=$((ctime-ltime))
	
	if [ $? -eq 0 ]; then
		
		iptables -w -t mangle -vnxL Panda_bw_output |sed '1,2d' > ${tempo}
		iptables -w -t mangle -vnxL Panda_bw_input |sed '1,2d' > ${tempi}
		
		sed '1d' /var/run/panda > ${templast}

		echo ${ctime} >/var/run/panda 
		while read -r -u5 ip last_input last_output current ; read -r -u3 pkti bytesi ino; read -r -u4 pkto byteso outo; do
			local all_input=$((bytesi-byteso))
			local all_output=$((byteso))
			local this_input=$((all_input-last_input))
			local this_output=$((all_output-last_output))
			printf "%15s %20s %20s %10s %10s\n" ${ip} ${all_input} ${all_output} $((this_input*1000/span)) $((this_output*1000/span))
			#echo -e "${ip}\t ${all_input}\t\t ${all_output}\t\t $((this_input*1000/span))\t\t $((this_output*1000/span))"
		done 5< ${templast} 3<${tempi} 4<${tempo} >>/var/run/panda
	fi

	rm ${tempi}
	rm ${tempo}
	rm ${templast}

}

function report_bw(){
	printf "%15s %20s %20s %10s %10s\n" "IP" "TotalInbound" "TotalOutbound" "Ingress BW" "Egress BW"
	#echo -e "IP\t\t Total Inbound\t Total Outbound\t Ingress BW\t Egress BW"
	sed '1d' /var/run/panda
}



function ip_to_int(){
	IFS=. ip=(${1})
	echo $((ip[0]*0x1000000+ip[1]*0x10000+ip[2]*0x100+ip[3]))
}

function int_to_ip(){
	echo -n $(($(($(($((${1}/256))/256))/256))%256)).
	echo -n $(($(($((${1}/256))/256))%256)).
	echo -n $(($((${1}/256))%256)).
	echo $((${1}%256)) 
}

# 24->0xffffff00
# 8->0xff000000
function CIDR_to_mask(){
	echo $(((0xffffffff<<(32-${1}))&0xffffffff))
}

function ip_in_net(){
	local ip_to_check=$1
	local ip_of_net=$2
	local mask=$3
	local int_check=$(ip_to_int ${ip_to_check})
	local int_net=$(ip_to_int ${ip_of_net})
	local int_mask=$(ip_to_int ${mask})
	local net_prefix=$((int_net&int_mask))
	local mask_prefix=$((int_check&int_mask))
	if [ ${net_prefix} -eq ${mask_prefix} ] ; then
		return 0
	else
		return 1
	fi
}	

function ip_mask_foreach(){
	local callback=$1
	[ "$#" -ge 1 ] && shift
	local ip=$1
	[ "$#" -ge 1 ] && shift
	local mask=$1
	[ "$#" -ge 1 ] && shift
	local ip_int=$(ip_to_int ${ip})
	local mask_int=$(ip_to_int ${mask})
	# number of ips in the CIDR
	local mask_not=$(((~mask_int)&0xffffffff))
	local ip_prefix=$((ip_int&mask_int))
	for (( i=1 ; i<${mask_not} ; ++i )); do
		#int reper of new ip
		local nip=$((${ip_prefix}|i))
		#string reper of new ip
		local nipstr=$(int_to_ip nip)
		#call callback index,stringofip
		${callback} ${i} ${nipstr} $@
	done
}

function _bw_remove_tc_wan(){
	local wan=$1
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))
	echo "tc qdisc del dev ${ifstr} ingress"
	
	echo "tc qdisc del dev ${ifstr} root"

}

function bw_remove_tc(){
	cat <<EOF


ip link set dev ifb0 down
ip link set dev ifb1 down

tc qdisc del dev ifb0 root 
tc qdisc del dev ifb1 root


EOF
	config_load panda
	wan_index=0
	config_foreach _bw_remove_tc_wan wan
}

function calc_total_for_wans(){
	local section=$1

	local upload
	config_get upload ${section} upload
	
	local download
	config_get download ${section} download

	utotal=$((utotal+upload))
	dtotal=$((dtotal+download))
}


function _bw_create_tc_wan(){
	local wan=$1
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))
	
	local upload
	config_get upload ${wan} upload
	local download
	config_get download ${wan} download
	local r2q=$((upload*125/1500/10))

	#add a dummy qdisc in case there is no qdisc
	echo "tc qdisc add dev ${ifstr} root handle 1: fq_codel"

	cat <<EOF
tc filter add dev ${ifstr} protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ifb0

tc qdisc add dev ${ifstr} ingress
tc filter add dev ${ifstr} parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ifb1

EOF
}

function bw_create_tc_basic(){
	config_load panda
	

	local umax
	config_get umax global per_user_upload

	local dmax
	config_get dmax global per_user_download

	utotal=0
	dtotal=0
	
	config_foreach calc_total_for_wans wan

	local umin=$((umax/10))
	local dmin=$((dmax/10))

	local r2q_upload=$((umin * 125 /1500))
	local r2q_download=$((dmin * 125 /1500))

	cat <<EOF

# ifb0 for upload bw limit
tc qdisc add dev ifb0 root handle 1: htb default ffff r2q ${r2q_upload}
tc class add dev ifb0 parent 1: classid 1:ffff htb rate ${utotal}kbit


# ifb1 for download bw limit
tc qdisc add dev ifb1 root handle 1: htb default ffff r2q ${r2q_download}
tc class add dev ifb1 parent 1: classid 1:ffff htb rate ${dtotal}kbit

ip link set dev ifb0 up
ip link set dev ifb1 up

EOF
	wan_index=0
	config_foreach _bw_create_tc_wan wan
}

function _bw_create_tc_ip(){
	local index=$1
	local ip=$2
	local umin=$3
	local dmin=$4
	local umax=$5
	local dmax=$6
	printf "tc class add dev ifb0 parent 1:ffff classid 1:%x htb rate %dkbit ceil %dkbit prio 1\n" ${index} ${umin} ${umax}
	printf "tc filter add dev ifb0 protocol ip parent 1: prio 1 handle 0x%x00/0x00ffff00 fw flowid 1:%x\n" ${index} ${index}
	printf "tc class add dev ifb1 parent 1:ffff classid 1:%x htb rate %dkbit ceil %dkbit prio 1\n" ${index} ${dmin} ${dmax}
	printf "tc filter add dev ifb1 protocol ip parent 1: prio 1 handle 0x%x00/0x00ffff00 fw flowid 1:%x\n" ${index} ${index} 

}



function bw_remove_ipt(){
	cat <<EOF
iptables -F Panda_bw -t mangle
iptables -F Panda_bw_input -t mangle
iptables -F Panda_bw_output -t mangle

iptables -X Panda_bw -t mangle
iptables -X Panda_bw_input -t mangle
iptables -X Panda_bw_output -t mangle
EOF
}

function bw_create_ipt_basic(){
	cat <<EOF
iptables -N Panda_bw -t mangle
iptables -N Panda_bw_input -t mangle
iptables -N Panda_bw_output -t mangle

iptables -A Panda_bw -t mangle -j CONNMARK --restore-mark --mask 0x00ffff00
iptables -A Panda_bw -t mangle -j Panda_bw_output
iptables -A Panda_bw -t mangle -j Panda_bw_input

iptables -A Panda_bw -t mangle -j CONNMARK --save-mark --mask 0x00ffff00
EOF
}

function _bw_create_ipt_ip(){
	local index=$1
	local ip=$2
	local gw=$3

	printf "iptables -A Panda_bw_input -t mangle -m mark --mark 0x%x00/0x00ffff00\n" ${index}
	printf "iptables -A Panda_bw_output -t mangle -s %s ! -d %s -j MARK --set-xmark 0x%x00/0x00ffff00\n" ${ip} ${gw} ${index}
}

function bw_remove(){
	bw_remove_ipt
	bw_remove_tc
}

function bw_create_ip(){
	index=$1
	ip=$2
	
	config_load network
	
	local gw
	config_get gw lan ipaddr
	
	config_load panda

	local umax
	config_get umax global per_user_upload

	local dmax
	config_get dmax global per_user_download

	local umin=$((umax/10))
	local dmin=$((dmax/10))
	
	_bw_create_ipt_ip ${index} ${ip} ${gw}
	_bw_create_tc_ip ${index} ${ip} ${umin} ${dmin} ${umax} ${dmax}
	
}

function bw_create(){
	config_load network

	bw_create_ipt_basic
	bw_create_tc_basic
}
