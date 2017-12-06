#!/bin/bash

nc -zv localhost $OGP_LISTEN_PORT

# monitorstring=$(nc -zv localhost $OGP_LISTEN_PORT)
# echo $monitorstring

# opencount=$(echo "$monitorstring" | grep -oh 'open' | wc -w)
# echo $opencount

# if [ "$opencount" -gt "0" ]
# then
#   echo "PASS"
#   exit 0
# else
#   echo "FAIL"
#   exit 1
# fi



# #Always Pass Test
# echo "PASS"
# exit 0
