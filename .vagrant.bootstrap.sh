#!/bin/bash

yum install -y rsync

# add user "storageuser" for running the tests with
useradd -m -s /bin/bash -U storageuser -u 666 --groups wheel
cp -pr /home/vagrant/.ssh /home/storageuser/
chown -R storageuser:storageuser /home/storageuser
#echo "%storageuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/storageuser
