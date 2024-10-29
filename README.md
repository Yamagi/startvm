# StartVM

StartVM (*startvm*) is a shell script to run and manage Bhyve virtual
machines. It's a simple wrapper, indented to ease starting and stopping
Bhyve VMs.


## Installation

To install this script, just clone the Github repository and symlink
*startvm* somewhere into your path. Rename *system.cfg.sample* to
*system.cfg* and edit it to match your needs. The file must be in the
same directory as the script itself!

The following kernel modules must be loaded:
* `if_bridge.ko`
* `if_tuntap.ko`
* `nmdm.ko`
* `vmm.ko`

The following ports are required:
* `sysutils/uefi-edk2-bhyve` (or any other compatible UEFI bootrom)
* `net/tigervnc-client` (optional)


## Usage

Create a new directory in your VMDIR. The directory name is used as VM
name, so do not use any character forbidden by Bhyve. Put a *bhyve.cfg*
into it. If you need to override global options, put a *startvm.cfg*
beside it. An example config is supplied. Now you're ready to start your
VM:

    Usage: ./startvm.sh [vmname] cmd
    
    Commands:
     - cons:   Open a serial console to the guest
     - halt:   Send an ACPI shutdown request to the guest
     - help:   This message
     - kill:   Kill the VM
     - list:   List all known VMs
     - run:    Run the VM
     - status: Show status
     - vnc:    Run vncviewer or print the VNC port
