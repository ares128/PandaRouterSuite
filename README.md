Welcome to Panda Router Suite!
==========================


There is everything you need for a small network router.
Bandwidth usage monitor, Per user bandwidth limit, QOS, Multi Wan balancing.

#Currently tested on LEDE 17.01.0#

Usage
------------------

- Copy everything to a folder in your router.
- Remove anything about QOS(qos-script,sqm,wsharper),multi wan balancing(mwan3).
- Install prerequisites
	

		opkg update
		
		opkg install ip bash kmod-sched kmod-sched-cake kmod-sched-connmark kmod-sched-core iptables iptables-mod-conntrack-extra iptables-mod-iface iptables-mod-ipopt tc kmod-sched-connmark kmod-ifb ipset
 

- Change wan interface to bridged mode
- Set a different metric on each Wan interface.
- Edit your config file. You can find a example in config folder.
- To install, run **./setup.sh install** in folder where u put the files.
- To monitor bandwidth per user, run **./panda.sh report**
- To uninstall, run **./setup.sh uninstall**

-------------
Limitations
-------------

 - Some kernel version is not supported
 - Ipv4 support only.
 - must use a bridged interface on each device.
 - Max supporting a subnet of Class B network in lan.
 - Max supporting wan number is 14. (But this can be extended)

-------------------------

TODO LIST
-------------

 1. Add procd init.d script
 2. Add luci interface
 3. Track wan status by ping dns and disable the failed wan.
 4. Add IPv6 support
 5. Auto detect the upload and download speed for wan.
 6. Use *rateest* to do a better balancing on multi wan.
 7. Add the concept of group, so that we can apply different bandwidth limit on different set of IPs.
 8. Change per_user_limit to percetage according to all bandwidth available.
 9. make a more reasonable hfsc scheam.

------------------------------------------
Configuration File
--------------------
This is a guide to write your config file.

### Global section ###
There is only one global section. **PLS** do not forgot the second global

	config global 'global'
		option long_connection '512'
		option per_user_upload '400'
		option per_user_download '500'
The *long_connection* parameter is that when a connection (if it is not in highest priority) have transfered more bytes than this value. The QOS will send it to lowest priority queue. // TODO set to 0 will disable it. Value is in kbytes. 

The *per_user_upload* and *per_user_download* parameter is the bandwidth limit for each user. Value is in kbit. 

### wan section ###
Write a section for each wan in config file.

	config wan 'wan2'
	       option overhead '8'
	       option download '3500'
	       option upload '576'
	
- The name of the section **wan2** shoud be identical to the name in network config.
- The *download* and *upload* parameter is in kbit, it will affect how wan is balanced and the QOS limitation. Please set to 90% of your actual bandwidth.
- The *overhead* parameter is set according to the network type from you to your ISP. Set to 0 is also ok.
>
> Refer to [Cake qdisc](https://www.bufferbloat.net/projects/codel/wiki/Cake/#extensive-framing-compensation-for-dsl-atm-pppoe).
> 
> Values could be
> #### for ADSL and ADSL2
> 
> - ipoa-vcmux (8)
> - ipoa-llcsnap (16)
> - bridged-vcmux (24) 
> - bridged-llcsnap (32)
> - pppoa-vcmux (10)
> - pppoa-llc (14) 
> - pppoe-vcmux (32)
> - pppoe-llcsnap (40)
>
> #### for VDSL
> 
> - pppoe-ptm (27)
> - bridged-ptm (19)
>
> #### for ethernet
> 
> - ether-phy (20)
> - ether-all (24)
> 

### Classify ###
Classify is used for QOS.
QOS have 4 different priority. 1-4. 1 is the highest priority and 4 is the lowest.
Classify config will match in order.

	config classify
		option priority '2'
		option proto 'tcp'
		option comment 'mail'
		option dest_port '587,25,110,995,143,993'

available option is *proto*, *comment*, *src_ip*, *src_port*, *dest_ip*, *dest_port*.
Ip can be *192.168.32.1* or *192.168.254.0/24*
port can have multi value.

### Rule ###
Rule is used for multi wan balancing.
Rule config will match in order. 

	config rule 'game'
		option policy 'wan2'
		option proto 'udp'
		option src_ip '192.168.254.111' 
available option is same as **classify**.

The *policy* parameter means which wan u want to go when matching the rule. It could be name of wan or **'balanced'**.


Special Thanks
----------------------------
This project refers to some other project.

### Multi wan balancing ###

referred to [Mwan3](https://github.com/Adze1502/mwan), but with much less function.



