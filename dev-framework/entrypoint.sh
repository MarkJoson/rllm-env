#!/bin/bash

set -e
mkdir -p /var/run/sshd
ssh-keygen -A
/usr/sbin/sshd -p 8022

if [ "$#" -eq 0 ]; then
  exec bash
else
  exec "$@"
fi