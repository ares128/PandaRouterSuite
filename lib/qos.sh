function _qos_remove_tc_wan(){
	
	local wan=$1
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))

	cat <<EOF

ip link set dev ${ifbstr} down

tc qdisc del dev ${ifbstr} root
tc qdisc del dev ${brstr} ingress

tc qdisc del dev ${brstr} root

EOF
}

function qos_remove_tc(){
	config_load panda

	wan_index=0
	config_foreach _qos_remove_tc_wan wan 	
}


function _qos_create_tc_wan_cake(){

	#interface br-xxx to do qos
	local wan=$1

	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))

	local upload
	config_get upload ${wan} upload

	local download
	config_get download ${wan} download

	local overhead
	config_get overhead ${wan} overhead


	cat <<EOF
tc qdisc add dev ${brstr} ingress
tc filter add dev ${brstr} parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ${ifbstr}

EOF

	if [ -n "${overhead}" ] ; then
		echo "tc qdisc add dev ${brstr} root handle 1: cake bandwidth ${upload}kbit internet diffserv4 srchost overhead ${overhead}"
		echo "tc qdisc add dev ${ifbstr} root handle 1: cake bandwidth ${download}kbit internet diffserv4 srchost overhead ${overhead}"
	else
		echo "tc qdisc add dev ${brstr} root handle 1: cake bandwidth ${upload}kbit internet diffserv4 srchost"
		echo "tc qdisc add dev ${ifbstr} root handle 1: cake bandwidth ${download}kbit internet diffserv4 srchost"
	fi


	




	printf "ip link set dev %s up\n" ${ifbstr}
}

function _qos_create_tc_wan_hfsc(){
	local wan=$1
	local default_priority=$2
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))

	local upload
	config_get upload ${wan} upload

	local download
	config_get download ${wan} download

	local u1=$((upload/2)) 
	local u2=$((upload/2))
	local u3=$((upload/3))
	local u4=$((upload/6))

	local d1=$((download/2)) 
	local d2=$((download/2))
	local d3=$((download/3))
	local d4=$((download/6))


	cat <<EOF
tc qdisc add dev ${brstr} root handle 1: hfsc default 1${default_priority}
tc class add dev ${brstr} parent 1: classid 1:1 hfsc sc m1 ${upload}kbit d 10ms m2 ${upload}kbit ul rate ${upload}kbit 

tc class add dev ${brstr} parent 1:1 classid 1:11 hfsc rt m1 ${upload}kbit d 20ms m2 ${u1}kbit 
tc class add dev ${brstr} parent 1:1 classid 1:12 hfsc ls rate ${u2}kbit ul rate ${upload}kbit 
tc class add dev ${brstr} parent 1:1 classid 1:13 hfsc ls rate ${u3}kbit ul rate ${upload}kbit 
tc class add dev ${brstr} parent 1:1 classid 1:14 hfsc ls rate ${u4}kbit ul rate ${upload}kbit 


tc filter add dev ${brstr} parent 1: protocol ip prio 5 handle 0x10/0xf0 fw flowid 1:11
tc filter add dev ${brstr} parent 1: protocol ip prio 4 handle 0x20/0xf0 fw flowid 1:12
tc filter add dev ${brstr} parent 1: protocol ip prio 3 handle 0x30/0xf0 fw flowid 1:13
tc filter add dev ${brstr} parent 1: protocol ip prio 2 handle 0x40/0xf0 fw flowid 1:14


tc qdisc add dev ${brstr} ingress
tc filter add dev ${brstr} parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ${ifbstr}

tc qdisc add dev ${ifbstr} root handle 1: hfsc default 1${default_priority}
tc class add dev ${ifbstr} parent 1: classid 1:1 hfsc sc m1 ${download}kbit d 10ms m2 ${download}kbit ul rate ${download}kbit 

tc class add dev ${ifbstr} parent 1:1 classid 1:11 hfsc rt m1 ${download}kbit d 20ms m2 ${d1}kbit 
tc class add dev ${ifbstr} parent 1:1 classid 1:12 hfsc ls rate ${d2}kbit ul rate ${download}kbit 
tc class add dev ${ifbstr} parent 1:1 classid 1:13 hfsc ls rate ${d3}kbit ul rate ${download}kbit 
tc class add dev ${ifbstr} parent 1:1 classid 1:14 hfsc ls rate ${d4}kbit ul rate ${download}kbit 


tc filter add dev ${ifbstr} parent 1: protocol ip prio 5 handle 0x10/0xf0 fw flowid 1:11
tc filter add dev ${ifbstr} parent 1: protocol ip prio 4 handle 0x20/0xf0 fw flowid 1:12
tc filter add dev ${ifbstr} parent 1: protocol ip prio 3 handle 0x30/0xf0 fw flowid 1:13
tc filter add dev ${ifbstr} parent 1: protocol ip prio 2 handle 0x40/0xf0 fw flowid 1:14


ip link set dev ${ifbstr} up
EOF
}



function _qos_create_tc_wan_htb(){
	local wan=$1
	local default_priority=$2
	local ifstr=$(uci -p /var/state get network.${wan}.device 2> /dev/null)
	local brstr=$(uci -p /var/state get network.${wan}.ifname 2> /dev/null)
	local ifbstr="ifb"$((wan_index+2))
	wan_index=$((wan_index + 1 ))

	local upload
	config_get upload ${wan} upload

	local download
	config_get download ${wan} download

	local r2q_upload=$((upload*125/1500/10))
	local r2q_download=$((download*125/1500/10))

	cat <<EOF
tc qdisc add dev ${brstr} root handle 1: htb default 1${default_priority} r2q ${r2q_upload}
tc class add dev ${brstr} parent 1: classid 1:1 htb rate ${upload}kbit prio 1
EOF

	for i in $(seq 1 4) ; do
		local rate=$((upload*(5-i)/10))
		printf "tc class add dev %s parent 1:1 classid 1:1%d htb rate %dkbit ceil %dkbit prio %d\n" ${brstr} ${i} ${rate} ${upload} $((6-i))
		printf "tc filter add dev %s parent 1: protocol ip prio %d handle 0x%x0/0xf0 fw flowid 1:1%d\n" ${brstr} $((6-i)) ${i} ${i}
	done

	

	cat <<EOF
tc qdisc add dev ${brstr} ingress
tc filter add dev ${brstr} parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ${ifbstr}

tc qdisc add dev ${ifbstr} root handle 1: htb default 1${default_priority} r2q ${r2q_download}
tc class add dev ${ifbstr} parent 1: classid 1:1 htb rate ${download}kbit
EOF
	for i in $(seq 1 4) ; do
		local rate=$((download*(5-i)/10))
		printf "tc class add dev %s parent 1:1 classid 1:1%d htb rate %dkbit ceil %dkbit prio %d\n" ${ifbstr} ${i} ${rate} ${download} $((i+1))
		printf "tc filter add dev %s parent 1: protocol ip prio %d handle 0x%x0/0xf0 fw flowid 1:1%d\n" ${ifbstr} $((i+1)) ${i} ${i}
	done

	printf "ip link set dev %s up\n" ${ifbstr}
}


function qos_create_tc_cake(){


	config_load panda

	wan_index=0
	config_foreach _qos_create_tc_wan_cake wan	
	
}

function qos_create_tc(){
	local default_priority

        config_load panda
        config_get default_priority global default_priority "3"

	config_load panda

	wan_index=0
	config_foreach _qos_create_tc_wan_hfsc wan ${default_priority}	
	
}


function _qos_create_ipt_iter(){
	local classify=$1

	local rule=$1
	local str=""
	rule_to_ipt str ${rule}

	local priority
	config_get priority ${rule} priority

	if [ -n "${priority}" ] ; then
		echo "iptables -A Panda_qos_firstcheck -t mangle -m mark --mark 0/0xf0 ${str} -j MARK --set-mark $((priority*16))/0xf0"
	fi

}



function _qos_create_ipt_iter_cake(){
	local classify=$1

	local rule=$1
	local str=""
	rule_to_ipt str ${rule}

	local priority
	config_get priority ${rule} priority

	if [ -n "${priority}" ] ; then
		if [ "${priority}" -eq "1" ] ; then
			echo "iptables -A Panda_qos_firstcheck -t mangle -m mark --mark 0/0xf0 ${str} -j DSCP --set-dscp-class EF"
		elif [ "${priority}" -eq "2" ] ; then
			echo "iptables -A Panda_qos_firstcheck -t mangle -m mark --mark 0/0xf0 ${str} -j DSCP --set-dscp-class CS2"
		elif [ "${priority}" -eq "4" ] ; then
			echo "iptables -A Panda_qos_firstcheck -t mangle -m mark --mark 0/0xf0 ${str} -j DSCP --set-dscp-class CS1"
		else
			echo "iptables -A Panda_qos_firstcheck -t mangle -m mark --mark 0/0xf0 ${str} -j DSCP --set-dscp-class CS0"
		fi
	fi

}

#refer https://github.com/kdarbyshirebryant/sch_cake/blob/master/sch_cake.c
#/*  Further pruned list of traffic classes for four-class system:
# *
# *	    Latency Sensitive  (CS7, CS6, EF, VA, CS5, CS4)
# *	    Streaming Media    (AF4x, AF3x, CS3, AF2x, TOS4, CS2, TOS1)
# *	    Best Effort        (CS0, AF1x, TOS2, and those not specified)
# *	    Background Traffic (CS1)
# *
# *		Total 4 traffic classes.
# */

#/*	Pruned list of traffic classes for typical applications:
# *
# *		Network Control          (CS6, CS7)
# *		Minimum Latency          (EF, VA, CS5, CS4)
# *		Interactive Shell        (CS2, TOS1)
# *		Low Latency Transactions (AF2x, TOS4)
# *		Video Streaming          (AF4x, AF3x, CS3)
# *		Bog Standard             (CS0 etc.)
# *		High Throughput          (AF1x, TOS2)
# *		Background Traffic       (CS1)
# *
# *		Total 8 traffic classes.
#*/

function qos_create_ipt_cake(){
	local long_connection
	config_get long_connection global long_connection "128"
	cat <<EOF
iptables -N Panda_qos -t mangle
iptables -N Panda_qos_firstcheck -t mangle
iptables -N Panda_qos_recheck -t mangle


iptables -A Panda_qos -t mangle -j Panda_qos_firstcheck -m dscp --dscp 0
iptables -A Panda_qos -t mangle -j Panda_qos_recheck


iptables -A Panda_qos_recheck -t mangle -p udp --dport 53 -j DSCP --set-dscp-class CS4
iptables -A Panda_qos_recheck -t mangle -p icmp -j DSCP --set-dscp-class CS5
iptables -A Panda_qos_recheck -t mangle -m connbytes --connbytes ${long_connection}000 --connbytes-dir both --connbytes-mode bytes -m dscp ! --dscp-class EF -j DSCP --set-dscp-class CS1

EOF

config_foreach _qos_create_ipt_iter_cake classify
}
function qos_create_ipt(){
	local default_level
	config_load panda
	config_get default_level global default_priority "3"
	local long_connection
	config_get long_connection global long_connection "128"
	cat <<EOF
iptables -N Panda_qos -t mangle
iptables -N Panda_qos_firstcheck -t mangle
iptables -N Panda_qos_recheck -t mangle

iptables -A Panda_qos -t mangle -j CONNMARK --restore-mark --mask 0xf0
iptables -A Panda_qos -t mangle -j Panda_qos_firstcheck -m mark --mark 0/0xf0
iptables -A Panda_qos -t mangle -j Panda_qos_recheck
EOF
	printf "iptables -A Panda_qos -t mangle -j MARK --set-mark 0x%x0/0xf0 -m mark --mark 0/0xf0\n" ${default_level}
	cat <<EOF
iptables -A Panda_qos -t mangle -j CONNMARK --save-mark --mask 0xf0

iptables -A Panda_qos -t mangle -p tcp -m tcp --tcp-flags ALL SYN -j MARK --set-mark 0x20/0xf0
iptables -A Panda_qos -t mangle -p tcp -m tcp --tcp-flags ALL RST -j MARK --set-mark 0x20/0xf0
iptables -A Panda_qos -t mangle -p tcp -m tcp --tcp-flags ALL FIN -j MARK --set-mark 0x20/0xf0

iptables -A Panda_qos_recheck -t mangle -p udp --dport 53 -j MARK --set-mark 0x20/0xf0
iptables -A Panda_qos_recheck -t mangle -p icmp -j MARK --set-mark 0x10/0xf0
iptables -A Panda_qos_recheck -t mangle -m connbytes --connbytes ${long_connection}000 --connbytes-dir both --connbytes-mode bytes -m mark ! --mark 0x10/0xf0 -j MARK --set-mark 0x40/0xf0
EOF
#TODO qos_check

	config_foreach _qos_create_ipt_iter classify 
}

function qos_remove_ipt(){
	cat <<EOF
iptables -F Panda_qos_recheck -t mangle
iptables -F Panda_qos_firstcheck -t mangle
iptables -F Panda_qos -t mangle

iptables -X Panda_qos_recheck -t mangle
iptables -X Panda_qos_firstcheck -t mangle
iptables -X Panda_qos -t mangle
EOF
}

function qos_create(){
	qos_create_ipt
	qos_create_tc
}

function qos_remove(){
	qos_remove_ipt
	qos_remove_tc
}
