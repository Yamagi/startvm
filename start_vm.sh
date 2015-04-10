#!/bin/sh

# Copyright (c) 2014 Yamagi Burmeister
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

# -------------------------------------------------------------------- #

# Simple script to run a Bhvye virtual machine. You need to edit this
# script to match your setup! Before running this script make sure 
# that the following kernel modules are loaded:
#  - if_bridge.ko
#  - if_tap.ko
#  - nmdm.ko
#  - vmm.ko
#
# All instances of this script must share the same configuration dir,
# otherwise strange things will happen. To boot other guests beside
# FreeBSD the sysutils/grub2-bhyve must be installed.

# -------------------------------------------------------------------- #

# Source system wide configuration
SCRIPTPATH=`readlink -f "$0"`
SCRIPTPATH=`dirname "$SCRIPTPATH"`
. $SCRIPTPATH/system.cfg

# -------------------------------------------------------------------- #

# Print usage.
usage() {
	echo "Usage: ./startvm.sh config_file cmd"
	echo ""
	echo "Commands:"
	echo " - cons:   Open a serial console to the guest"
	echo " - halt:   Send an ACPI shutdown request to the guest"
	echo " - help:   This message"
	echo " - kill:   Kill the VM"
	echo " - run:    Run the VM"
	echo " - status: Show status"
	exit 1
}

# Debug output.
dbg() {
	if [ $DEBUG -ne 0 ] ; then
		echo $1
	fi
}

# Checks if $BRIDGE exists and creates
# it if necessary.
createbridge() {
	/sbin/ifconfig $BRIDGE > /dev/null

	if [ $? -ne 0 ] ; then
		dbg "Creating $BRIDGE"

		/sbin/ifconfig $BRIDGE create
		/sbin/ifconfig $BRIDGE addm $EXTNIC stp $EXTNIC up
	fi
}

# Checks if the "up on open" sysctl for
# tap devices is set. If necessary it's
# value is changed to 1.
checkuponopen() {
	if [ `/sbin/sysctl -n net.link.tap.up_on_open` -ne 1 ] ; then
		dbg "Setting net.link.tap.up_on_open to 1"

		/sbin/sysctl net.link.tap.up_on_open=1 > /dev/null 2>&1 
	fi
}

# Generates a unique ID for this instance.
generateid() {
	# Lock
    while [ true ] ; do
		if [ -e $RTDIR/id.lock ] ; then
			sleep 0.1
		else
			touch $RTDIR/id.lock
			break
		fi
	done

	# Create ID
	if [ -e $RTDIR/id ] ; then
		. $RTDIR/id
		UID=$((UID + 1))
	else
		UID=0
	fi

	echo "UID=$UID" > $RTDIR/id 

	# Unlock
	rm $RTDIR/id.lock

	return $UID
}

# Creates and configures a tap device.
#  $1 -> ID of the VM
createtap() {
	/sbin/ifconfig tap$1 > /dev/null 2>&1

	if [ $? -ne 0 ] ; then
		dbg "Creating tap$1"

		/sbin/ifconfig tap$1 create
		/sbin/ifconfig $BRIDGE addm tap$1 stp tap$1 up
		return $1
	else
		echo "tap$1 already existant"
		exit 1
	fi
}

# Transforms the process into a daemon.
becomedaemon() {
	dbg "Respawning a daemon"
	/usr/sbin/daemon -f $1 $2 daemon
}

# -------------------------------------------------------------------- #

# Opens a serial console session
# to the VM.
console() {
	if [ ! -e $RTDIR/$NAME.state ] ; then
		echo "VM is not running"
		exit 1
	fi

	. $RTDIR/$NAME.state 

	# Call cu
	dbg "Calling cu"
	echo "Type ~ + ^d to exit"
	/usr/bin/cu -s 9600 -l $NMDMB
	echo "Console closed"
}

# Shuts a VM down by sending SIGTERM
# It will generate an ACPI shutdown
# event and send it to the guest.
haltvm() {
 	if [ ! -e $RTDIR/$NAME.state ] ; then
		echo "VM is not running"
		exit 1
	fi

	. $RTDIR/$NAME.state 

 	if [ -z "$PID" ] ; then
		echo "VM is running, but Bhyve hasn't started yet"
		exit 1
	fi
 
	dbg "Sending SIGTERM to VM"
	kill -TERM $PID
}

# Kills a VM by sending SIGKILL.
killvm() {
  	if [ ! -e $RTDIR/$NAME.state ] ; then
		echo "VM is not running"
		exit 1
	fi

	. $RTDIR/$NAME.state 

	if [ -z "$PID" ] ; then
		echo "VM is running, but Bhyve hasn't started yet"
		exit 1
	fi

	dbg "Sending SIGKILL to VM"
	kill -KILL $PID
}

# Runs the VM.
runvm() {
	# Check if VM is still running
	if [ -e /dev/vmm/$NAME ] ; then
		echo "VM is still running."
		exit 1
	fi

	# Determine ID
	generateid
	ID=$?

	# Create the bridge
	createbridge

	# Create tap device
	checkuponopen
	createtap $ID
	TAP=tap$?

	# Determine nmdm interface to use
	NMDMA=/dev/nmdm_${ID}_${NAME}_A
	NMDMB=/dev/nmdm_${ID}_${NAME}_B

	while [ true ] ; do

 		# Save state
		dbg "Saving state to $RTDIR/$NAME.state" 
		echo "TAP=$TAP" > $RTDIR/$NAME.state
		echo "NMDMA=$NMDMA" >> $RTDIR/$NAME.state
		echo "NMDMB=$NMDMB" >> $RTDIR/$NAME.state 
		echo "ID=$ID" >> $RTDIR/$NAME.state

		# Loader
		if [ $LOADER = "bhyve" ] ; then
			dbg "Calling bhyveload"
			if [ $BOOT = "cdrom" ] ; then
				dbg "Booting from CDROM"
				/usr/sbin/bhyveload -m $MEMORY -d $CDROM -c $NMDMA $NAME
			elif [ $BOOT = "hd" ] ; then
				dbg "Booting from harddisk"
				/usr/sbin/bhyveload -m $MEMORY -d $HD -c $NMDMA $NAME
			fi
		fi

		if [ $LOADER = "grub" ] ; then
			dbg "Calling grub-bhyve"

			# We need to write one bit into the virtual nullmodem
			# cable, otherwise grub-bhyve will wait forever for
			# user input. Wait 0.5 seconds for nmdm to open. This
			# is a dirty work around against possible races.
			true > $NMDMB &
			sleep 0.5

			/usr/local/sbin/grub-bhyve -r $BOOT -m $MAP -M $MEMORY -c $NMDMA $NAME &
			PID=$!

			wait $PID
		fi

		# Start VM
		dbg "Calling bhyve"

		if [ $CDROM = 0 ] ; then
			/usr/sbin/bhyve -A -H -P -s 0:0,hostbridge -s 1:0,lpc \
				-s 2:0,virtio-net,$TAP -s 3:0,ahci-hd,$HD -s 4:0,virtio-rnd \
				-l com1,$NMDMA -c $CPUS -m $MEMORY $NAME > /dev/null 2>&1 & 
		else
			/usr/sbin/bhyve -A -H -P -s 0:0,hostbridge -s 1:0,lpc -s 2:0,virtio-net,$TAP \
				-s 3:0,ahci-hd,$HD -s 4:0,ahci-cd,$CDROM -s 5:0,virtio-rnd \
				-l com1,$NMDMA -c $CPUS -m $MEMORY $NAME > /dev/null 2>&1 &
		fi

		PID=$!

		# Save PID
		dbg "Saving PID to $RTDIR/$NAME.state" 
		echo "PID=$PID" >> $RTDIR/$NAME.state

		# Wait for bhyve
		wait $PID

		# Return codes:
		# - 0: reset
		# - 1: powered off
		# - 2: halted
		# - 3: triple fault
		# - other: crash
		if [ $? -ne 0 ] ; then
			dbg "Shutdown"
			break
		fi

        # Grub is not reboot save. We need to
		# recreate the VM, otherwise Bhyve
		# will crash.
		if [ $LOADER = "grub" ] ; then
			/usr/sbin/bhyvectl --destroy --vm=$NAME
		fi

		dbg "Reboot"
	done

	# Cleanup
	/usr/sbin/bhyvectl --destroy --vm=$NAME
	/sbin/ifconfig $BRIDGE deletem $TAP up
	/sbin/ifconfig $TAP destroy
	rm $RTDIR/$NAME.state

	# Cleanup if last process
	ls $RTDIR/*state > /dev/null 2>&1

	if [ $? -ne 0 ] ; then
		dbg "Last process, removing state directory"
		rm -Rf $RTDIR
	fi
}

# Prints the status of VM.
status() {
	if [ -e $RTDIR/$NAME.state ] ; then
		if [ -e /dev/vmm/$NAME ] ; then
			echo "Running"
		else
			echo "Stale state file"
		fi
	else
		if [ -e /dev/vmm/$NAME ] ; then
			echo "Stale VM instance"
		else
			echo "Stopped"
		fi
	fi
}

# -------------------------------------------------------------------- #

# Create state dir
mkdir -p $RTDIR

# Command line processing
if [ -z "$1" -o -z "$2" ] ; then
   usage
fi   

if [ ! -f "$1" ] ; then
	echo "$1 doesn't exists or is not a regular file"
	exit 1
fi

. $1

if [ $2 = "daemon" ] ; then
	runvm
else
	case $2 in
		cons)
			console
			;;
		halt)
			haltvm
			;;
		help)
			usage
			;;
		kill)
			killvm
			;;
		run)
			if [ $DAEMON -ne 0 ] ; then
				becomedaemon $0 $1
			else
				runvm
			fi
			;;
		status)
			status
			;;
		*)
			usage
			;;
	esac
fi
