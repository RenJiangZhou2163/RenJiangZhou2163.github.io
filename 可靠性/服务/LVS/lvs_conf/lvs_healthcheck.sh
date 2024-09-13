#!/bin/bash
LOG_DIR="/var/log/obs/obs-lvs/scriptlog/"
if [ ! -d "$lOG_DIR" ]; then
    mkdir -p ${LOG_DIR}
fi
LVS_LOG_FILE="${LOG_DIR}obs.obs-lvs.watch.log"
LVS_BAK_LOG_FILE="${LOG_DIR}obs.obs-lvs.watch.log.1"
LVS_LOG_FILE_LN="${LOG_DIR}obs.obs-lvs.watch.log.ln"
# 10M
FILE_SIZE=10485760
# 11M
FORCE_DELETE_LN_FILE_SIZE=11534336

function rename_log() {
    local log_size=$(ls -l "${LVS_LOG_FILE}" 2>/dev/null | awk '{print $5}')
    # greater than 10M
    if [ ${log_size} -gt ${FILE_SIZE} ]; then
        $(ln -s "${LVS_LOG_FILE}" "${LVS_LOG_FILE_LN}")
        if [ $? -eq 0 ]; then
            local log_size_recheck=$(ls -l "${LVS_LOG_FILE}" 2>/dev/null | awk '{print $5}')
            # greater than 10M, rename log
            if [ ${log_size_recheck} -gt ${FILE_SIZE} ]; then
                mv "${LVS_LOG_FILE}" "${LVS_BAK_LOG_FILE}"
                chmod 440 "${LVS_BAK_LOG_FILE}"
                #find max index,must to the first record
                queryResult=$(ls -lt $LOG_DIR | grep tar | head -n 1)
                if [ -z "$queryResult" ]; then
                    maxIndex=0
                else
                    #get lastest file name
                    lastestFileName=$(echo $queryResult | awk '{print $9}')
                    maxIndex=$(echo $lastestFileName | awk -F . '{print $5}')
                fi
                #tar file
                tar -zcvf "${LOG_DIR}obs.obs-lvs.watch.log.$((maxIndex + 1)).tar" $LVS_BAK_LOG_FILE
                rm -rf $LVS_BAK_LOG_FILE
                #delete old files
                tarFileNumber=$(ls -lt $LOG_DIR | grep tar | wc -l)
                if [ $tarFileNumber -gt 300 ]; then
                    oldestFile=$(ls -lt $LOG_DIR | grep tar | tail -n 1)
                    oldestFileName=$(echo $oldestFile | awk '{print $9}')
                    rm -rf "${LOG_DIR}$oldestFileName"
                fi
            fi
            rm -rf "${LOG_DIR}obs.obs-lvs.watch.log.ln"
        else
            # OS PowerOff, maybe ln file exists.
            # ln -s will fail and log file is greater than FORCE_DELETE_LN_FILE_SIZE, delete the ln file
            local log_size_delete_ln=$(ls -l "${LVS_LOG_FILE}" 2>/dev/null | awk '{print $5}')
            if [ ${log_size_delete_ln} -gt ${FORCE_DELETE_LN_FILE_SIZE} ]; then
                rm -rf "${LOG_DIR}obs.obs-lvs.watch.log.ln"
            fi
        fi
    fi
}

function log() {
    local date_str=$(date)
    local msg="$1"
    local log_str="["${date_str}"] ["${msg}"]"
    echo -e "${log_str}" >>"${LVS_LOG_FILE}"
    chmod 640 $LVS_LOG_FILE
    rename_log
}

function check_all_osc() {
    #when all osc node failed
    if [ ${checkport} -eq 443 -o ${checkport} -eq 5443 -o ${checkport} -eq 80 -o ${checkport} -eq 5080 ]; then
        ipvsadm -ln | grep "Route" | grep " 253 " | grep ":${checkport}"
        if [ ! $? -eq 0 ]; then
            vips_conf=$(cat /etc/keepalived/keepalived.conf | grep keepalived | grep conf)
            for vip_conf in $vips_conf; do
                if [ ! $vip_conf = "include" ]; then
                    vip=$(echo $vip_conf | grep -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
                    iptables_exist=$(check_iptables_exist ${vip})
                    if [ "${iptables_exist}" = "" ]; then
                        log "no active osc node exist, start to forbid ping , cmd is iptables -A OUTPUT -p icmp -s ${vip} -j DROP"
                        iptables -A OUTPUT -p icmp -s ${vip} -j DROP
                        log "execute cmd result is $?"
                    fi
                fi
            done
        fi
    fi
}

function parse_json() {
    echo $1 | sed 's/.*\"'$2'\":\([^,}]*\).*/\1/'
}

function check_iptables_exist() {
    echo $(iptables-save | grep $1 | grep icmp | grep DROP)
}

realip=$1
checkport=$2
checkport2=$3
if [ -z "${realip}" -o -z "${checkport}" ]; then
    log "the input ip ${realip} or the port ${checkport} is empty."
    exit 1
fi
check_all_osc
obsConf="/opt/obs/obs-lvs/conf/obs.conf"
function do_check() {
    # connect timeout 10s, transfer timeout 10s
    if [ ${checkport} -eq 53 ]; then
        domain=$(grep -E "^DOMAINNAME=" "${obsConf}" 2>/dev/null | awk -F'=' '{print $2}')
        if [ -z "${domain}" ]; then
            log "the domain is empty."
            exit 1
        fi
        dig_result=$(dig +short ${domain} @${realip} 2>/dev/null)
        if [ $? != 0 ]; then
            log "dns reponse error by dig +short ${domain} @${realip}"
            return 1
        fi
        #abnormal
        if [ -z "${dig_result}" ]; then
            log "No response from ${realip} by dig +short ${domain} @${realip}"
            return 1
        fi
        log "${realip}:${checkport} response is ${dig_result} "
        exit 255
    
    #get osc status, osc port (http:80/5080; https:443/5443)
    elif [ ${checkport} -eq 443 -o ${checkport} -eq 5443 -o ${checkport} -eq 10443 ]; then
        jsonr=$(curl -k --connect-timeout 8 -m 9 -X OPTIONS_DNS https://${realip}:${checkport}/dns --header 'Connection:close' 2>/dev/null)
    elif [ ${checkport} -eq 80 -o ${checkport} -eq 5080 -o ${checkport} -eq 7080 ]; then
        jsonr=$(curl --connect-timeout 8 -m 9 -X OPTIONS_DNS http://${realip}:${checkport}/dns --header 'Connection:close' 2>/dev/null)
    
    #get ls status, ls port (http:5180; https:5543)
    elif [ ${checkport} -eq 5543 ]; then
        jsonr=$(curl -k --connect-timeout 8 -m 9 -X OPTIONS_LVS https://${realip}:${checkport}/LS/sys --header 'Connection:close' 2>/dev/null)
    elif [ ${checkport} -eq 5180 ]; then
        jsonr=$(curl --connect-timeout 8 -m 9 -X OPTIONS_LVS http://${realip}:${checkport}/LS/sys --header 'Connection:close' 2>/dev/null)
    
    #get obs-proxy status, obs-proxy port (https:11443)
    elif [ ${checkport} -eq 11443 ]; then
        jsonr=$(curl -k --connect-timeout 8 -m 9 -X OPTIONS https://${realip}:${checkport}/health-check --header 'Connection:close' 2>/dev/null)
    else
        log "the port:${checkport} is unavailable."
    fi
    
    # when the server is down this may always print to the logfile. it's not need!
    if [ ! $? -eq 0 -o -z "$jsonr" ]; then
        log "the osc ${realip}:${checkport} is unavailable whith empty response." #get an empty response from the real server
        if [ ! -z ${checkport2} ]; then
            jsonr=$(curl --connect-timeout 8 -m 9 -X OPTIONS_DNS http://${realip}:${checkport2}/dns --header 'Connection:close' 2>/dev/null)
            if [ ! $? -eq 0 -o -z "$jsonr" ]; then
                log "the osc ${realip}:${checkport2} is unavailable whith empty response."
                return 1
            fi
        else
            return 1
        fi
    fi
    value=$(parse_json ${jsonr} "azFlag")
    if [ ! $? -eq 0 -o "${value}" = "1" -o "${value}" = "0" -o "${value}" = "3" ]; then
        vips_conf=$(cat /etc/keepalived/keepalived.conf | grep keepalived | grep conf)
        for vip_conf in $vips_conf; do
            if [ ! $vip_conf = "include" ]; then
                vip=$(echo $vip_conf | grep -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
                if [ "${value}" = "0" ]; then
                    iptables_exist=$(check_iptables_exist ${vip})
                    if [ "${iptables_exist}" = "" ]; then
                        log "lvs forbid ping iptables rule not exist, start to add it, cmd is iptables -A OUTPUT -p icmp -s ${vip} -j DROP"
                        iptables -A OUTPUT -p icmp -s ${vip} -j DROP
                        log "execute add cmd result is $?"
                    fi
                fi
                if [ "${value}" = "1" -o "${value}" = "3" ]; then
                    iptables_exist=$(check_iptables_exist ${vip})
                    if [ ! "${iptables_exist}" = "" ]; then
                        log "lvs forbid ping iptables rule exist, start to delete it, cmd is iptables -D OUTPUT -p icmp -s ${vip} -j DROP"
                        iptables -D OUTPUT -p icmp -s ${vip} -j DROP
                        log "execute delete cmd result is $?"
                    fi
                fi
            fi
        done
    fi
    value=$(parse_json ${jsonr} "uiFlag")
    if [ ! $? -eq 0 -o ! "${value}" = "1" ]; then
        if [ ! "${value}" = "0" ]; then
            log "the osc ${realip}:${checkport} is unavailable now. the response content is: ${jsonr}, exit 1"
            return 1
        fi
        log "the osc ${realip}:${checkport} is unavailable now. the response content is: ${jsonr}"
        return 2
    fi
    log "${realip}:${checkport} response is ${jsonr} "
    exit 255
}
result=255
for var in {1..3}; do
    do_check
    result=$?
    if [ ! ${result} -eq 255 ]; then
        log "check osc ${realip}:${checkport} fail, retry times ${var}"
    else
        break
    fi
done
exit ${result}
