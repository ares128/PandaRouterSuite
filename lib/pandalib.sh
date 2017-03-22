. /lib/functions.sh
. /lib/functions/network.sh

DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]] ;  then DIR="$PWD" ; fi

. $DIR/shared.sh
. $DIR/qos.sh
. $DIR/bw.sh
. $DIR/mwan.sh



function panda_checkwan(){
	
	config_load panda

	config_foreach check_wan_config wan
}



function create_ip(){
	index=$1
	ip=$2
	bw_create_ip ${index} ${ip}
}
function panda_report(){
	report_bw
}

function remove(){
	
	echo "iptables -F Panda -t mangle"
	echo "iptables -D PREROUTING -t mangle -j Panda"
	echo "iptables -D OUTPUT -t mangle -j Panda"
	echo "iptables -X Panda -t mangle"
	
	bw_remove
	qos_remove
	mwan_remove

	echo "rmmod sch_htb"
	echo "rmmod sch_cake"
	echo "rmmod ifb"


	if [ -e /var/run/panda ] ; then
		echo "rm /var/run/panda"
	fi

}


function create(){
	
	if [ -e /var/run/panda ] ; then
		stop
	fi

	echo "touch /var/run/panda"

	local num_wans=$(count_wan)
	echo "rmmod ifb"
	printf "insmod ifb numifbs=%d\n" $((num_wans+2))
	echo "rmmod sch_htb"
	echo "insmod sch_htb"

	echo "rmmod sch_cake"
	echo "insmod sch_cake"
	
	echo "iptables -N Panda -t mangle"
	echo "iptables -A PREROUTING -t mangle -j Panda"
	echo "iptables -A OUTPUT -t mangle -j Panda"
	bw_create
	echo "iptables -A Panda -t mangle -j Panda_bw"
	qos_create
	echo "iptables -A Panda -t mangle -j Panda_qos"
	mwan_create
	echo "iptables -A Panda -t mangle -j Panda_mwan"

	
}


function panda_checkarp(){

	if [ ! -e /var/run/panda ] ; then
		exit 2
	fi
	config_load network
	
	local gw
	config_get gw lan ipaddr

	local mask
	config_get mask lan netmask

	cat /proc/net/arp | sed "1 d" | awk '{print $1}' | while read -r ip ; do
		if  ip_in_net ${ip} ${gw} ${mask} ; then
			if ! record_has_ip ${ip} ; then
				record_add_ip ${ip}
			fi
		fi
	done
}

function panda_start(){
	create
}

function panda_stop(){
	

	remove
}


