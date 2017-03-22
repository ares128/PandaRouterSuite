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
		./panda.sh checkarp
		update_bw 
		sleep 10s
	done

	exit 1

}



function checkbw(){
	update_bw
}
case $1 in
	start|stop|checkbw)
		$*
	;;
	*)
		echo "should not start manually!"
	;;
esac





