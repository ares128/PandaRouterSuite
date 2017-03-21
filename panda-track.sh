#!/bin/bash
. lib/pandalib.sh

function stop(){
	if [ -e /var/run/panda-track.pid ] ; then
		kill $(cat /var/run/panda-track.pid) &> /dev/null
		rm /var/run/panda-track.pid
	fi
}

function start(){

	stop

	echo "$$" > /var/run/panda-track.pid

	while true; do
		panda_checkarp | sh
		update_bw 
		sleep 10s
	done

	exit 1

}

function checkarp(){
	panda_checkarp | sh -x
}

function checkbw(){
	update_bw
}
case $1 in
	start|stop|checkarp|checkbw)
		$*
	;;
	*)
		echo "should not start manually!"
	;;
esac





