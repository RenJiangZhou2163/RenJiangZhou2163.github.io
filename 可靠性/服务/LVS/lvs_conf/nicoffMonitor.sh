#!/bin/sh
ETH_CONFIG_DIR="/opt/obs/obs-lvs/script"
ETH_CONFIG_FILE="ethCard.conf"
function closeglro()
{
    local ret1=0
    local ret2=0
    local card=$1
    /sbin/ethtool -k ${card} |grep "generic-receive-offload" |grep " off " >>/dev/null 2>&1
    ret1=$?
    /sbin/ethtool -k ${card} |grep "large-receive-offload" |grep " off "  >>/dev/null 2>&1
    ret2=$?
    if [ 0 -ne ${ret1} -o 0 -ne ${ret1} ]
    then
        ethtool -K ${card} gro off
        ethtool -K ${card} lro off
    fi
    return 0
}
while IFS='' read -r line || [[ -n "$line" ]]; do
    ethcard=$line
    closeglro "$ethcard"    
done < $ETH_CONFIG_DIR/$ETH_CONFIG_FILE