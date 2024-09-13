#!/bin/sh
curPath=$(cd "$(dirname "$0")"; pwd)
logFile="${curPath}/vipMonitor.log"
keepalivedConfFiles="/etc/keepalived/keepalived_*.conf"
vipList=""
function shellLog()
{
    local logLine=""
    local logLevel=""
    local logLineNo=""
    if [ 3 != $# ]
    then
        echo "$(date +'%Y%m%d %H:%M:%S') ERROR: log input para is error,input para is $@"
        return 1
    fi
    logLevel="$1"
    logLineNo="$2"
    logLine="$3"
    if [ "ERROR" == "${logLevel}" ]
    then
        echo -e "\033[31m$(date +'%Y/%m/%d %H:%M:%S') line:$logLineNo $logLevel:$logLine\033[0m"
        echo -e "\033[31m$(date +'%Y/%m/%d %H:%M:%S') line:$logLineNo $logLevel:$logLine\033[0m" >>"${logFile}"
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') line:$logLineNo $logLevel:$logLine"
        echo "$(date +'%Y/%m/%d %H:%M:%S') line:$logLineNo $logLevel:$logLine">>"${logFile}"
    fi
    return 0
}
function logInfo()
{
    local lineNO=""
    lineNO=$(caller 0 |awk '{print $1}')
    shellLog "INFO" "$lineNO" "$@"
    if [ 0 -ne $? ]
    then
        return 1
    fi
    return 0
}
function logError()
{
    local lineNO=""
    lineNO=$(caller 0 |awk '{print $1}')
    shellLog "ERROR" "$lineNO" "$@"
    if [ 0 -ne $? ]
    then
        return 1
    fi
    return 0
}

#init log
function initlog()
{
    if [ ! -d "${curPath}" ]
    then
        mkdir -p "${curPath}"
    fi
    if [ ! -f "${logFile}" ]
    then
        touch "${logFile}"
    fi
    return 0
}

# 从配置文件中获取VIP
function getVipFromCfg()
{
    vipList=$(cat ${keepalivedConfFiles} | grep -w virtual_server | grep -w 5443 | awk '{print $2}')
    if [ $? != 0 ]
    then
        logError "Fail to get vip list from ${keepalivedConfFiles}."
        return 1
    fi
    return 0
}

# 检查VIP是否生效
function checkVips()
{
    local ret=""
    for i in ${vipList[@]}
    do 
        ret=$(ip addr | fgrep -w $i)
        if [ $? -eq 0 ]
        then
            continue
        fi
        # 不生效则重新加载Keepalived
        ret=$(service keepalived reload)
        logError "service keepalived reload. vip($i) ret($ret)"
    done
    return 0
}
initlog
getVipFromCfg
if [ $? -ne 0 ]
then
    exit 0
fi
k=1;
while(( $k<=4 ));
do
    checkVips
    let "k++";
    sleep 15;
done
exit 0