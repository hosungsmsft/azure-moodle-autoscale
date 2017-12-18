#!/bin/bash

STACKNAME="$1"
if [ $# != 1 ]; then
   echo "Usage:  $0 <stack name>"
fi

/usr/bin/az group delete -y --name ${STACKNAME}
echo "If there is an error above, you'll need to delete your stack from the GUI."
