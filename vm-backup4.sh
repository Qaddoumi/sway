#!/bin/bash

#sudo qemu-img convert -p -O qcow2 -c /run/media/moh/Mkohaa4TB/archBackup/vms/002-win11.qcow2 /var/lib/libvirt/images/002-win11.qcow2

sudo qemu-img convert -p -O qcow2 -c /var/lib/libvirt/images/002-win11.qcow2 /run/media/moh/Mkohaa4TB/archBackup/vms/002-win11.qcow2
sudo cp /etc/libvirt/qemu/002-win11.xml /run/media/moh/Mkohaa4TB/archBackup/vms/002-win11.xml

sudo qemu-img convert -p -O qcow2 -c /var/lib/libvirt/images/002-win11-clone.qcow2 /run/media/moh/Mkohaa4TB/archBackup/vms/002-win11-clone.qcow2
sudo cp /etc/libvirt/qemu/002-win11-clone.xml /run/media/moh/Mkohaa4TB/archBackup/vms/002-win11-clone.xml

sudo qemu-img convert -p -O qcow2 -c /var/lib/libvirt/images/003-win11.qcow2 /run/media/moh/Mkohaa4TB/archBackup/vms/003-win11.qcow2
sudo cp /etc/libvirt/qemu/003-win11-study.xml /run/media/moh/Mkohaa4TB/archBackup/vms/003-win11-study.xml


