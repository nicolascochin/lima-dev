#!/bin/bash

NAME=$1

# Check if a parameter is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <instance_name>"
  exit 1
fi

# Check if the provided instance name exists in limactl list output
if ! limactl list -q --log-level error | grep -qx "$1"; then
  echo "Error: Instance '$1' not found in limactl list."
  exit 1
fi

status=$(limactl list | grep $NAME | awk '{print $2}')
if [ "$status" == "Stopped" ]; then
  echo "Starting the VM $1"
  limactl start $1
fi

# Set the LIMA_INSTANCE variable and run the command
limactl shell --workdir /home/$1 --shell /bin/zsh $1
