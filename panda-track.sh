#!/bin/bash

DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]] ;  then DIR="$PWD" ; fi


. ${DIR}/lib/pandalib.sh

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
		./panda.sh checkbw 
		sleep 10s
	done

	exit 1

}


case $1 in
	start|stop)
		$*
	;;
	*)
		echo "should not start manually!"
	;;
esac





