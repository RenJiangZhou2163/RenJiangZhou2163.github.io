#!/bin/sh
curPath=$(
    cd "$(dirname "$0")"
    pwd
)
logFile="${curPath}/lvsMonitor.log"
#监控Keepalived服务
/etc/init.d/keepalived status
if [ ! $? -eq 0 ]; then
    echo "$(date +'%Y%m%d %H:%M:%S') /etc/init.d/keepalived restart" >>${logFile}
    /etc/init.d/keepalived restart >>${logFile}
    exit 0
fi
res=$(ipvsadm -ln --timeout)
tcp=$(echo $res | cut -d ' ' -f 6)
if [ "$tcp"!="1" ]; then
    echo "${date} ipvsadm --set 900 1 0"
    ipvsadm --set 900 1 0
fi
exit 0
