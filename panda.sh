#!/bin/bash
. lib/pandalib.sh


# depends on package:
# ip 			for ip rule add fwmark
# bash 			for script
# kmod-sched-cake	for qos
# kmod-sched
# kmod-sched-connmark
# kmod-sched-core
# iptables
# iptables-mod-conntrack-extra
# iptables-mod-iface
# iptables-mod-ipopt
# tc
# kmod-sched-connmark
# kmod-ifb
# ipset


#opkg install ip bash kmod-sched kmod-sched-cake kmod-sched-connmark kmod-sched-core iptables iptables-mod-conntrack-extra iptables-mod-iface iptables-mod-ipopt tc kmod-sched-connmark kmod-ifb ipset


function start(){
	panda_checkwan
	panda_start | sh -x
	./panda-track.sh start &
}

function stop(){
	./panda-track.sh stop
	panda_stop | sh -x
}


function report(){
	panda_report
}

function checkarp(){
	panda_checkarp | sh -x
}

case "$1" in 
	start|stop|report|checkarp)
		$*
	;;
	*)
		echo "start,stop,report"
	;;
esac
