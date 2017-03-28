#!/bin/sh

install(){
	opkg update
	opkg install ip bash kmod-sched kmod-sched-cake kmod-sched-connmark kmod-sched-core iptables iptables-mod-conntrack-extra iptables-mod-iface iptables-mod-ipopt tc kmod-sched-connmark kmod-ifb ipset
	
	mkdir /usr/lib/panda
	cp panda.sh /usr/lib/panda
	cp panda-track.sh /usr/lib/panda
	
	mkdir /usr/lib/panda/lib
	cp lib/* /usr/lib/panda/lib

	cp init/panda /etc/init.d/panda

	/etc/init.d/panda enable

}

uninstall(){
	/etc/init.d/panda stop
	rm -rf /usr/lib/panda

	rm /etc/init.d/panda
}

case "$1" in 
	install|uninstall)
		$*
	;;
	*)
		echo "setup.sh install/uninstall"
	;;
esac
