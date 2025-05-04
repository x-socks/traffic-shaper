#!/bin/bash
#
# 系统级智能流量控制方案 (Linux)
# 此脚本使用Linux的流量控制工具(tc)和带宽监控来避开VPS限速策略
# 限速触发条件:
# 1. 连续下载超过5GB流量
# 2. 占用带宽超过50Mbps达5分钟以上
#

# 颜色代码
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置参数
INTERFACE="eth0"                # 网络接口，根据你的VPS情况修改
MAX_BANDWIDTH=48                # 单位Mbps (略低于触发阈值50Mbps)
BANDWIDTH_TIME_LIMIT=300        # 5分钟 (秒)
MAX_CONTINUOUS_DATA=4800        # 单位MB (略低于触发阈值5GB)
PAUSE_DURATION=180              # 暂停时间3分钟 (秒)
MONITOR_INTERVAL=5              # 监控间隔 (秒)
LOG_FILE="/var/log/traffic-shaper.log"

# 依赖检查
check_dependencies() {
    echo -e "${BLUE}[*] 检查依赖...${NC}"
    for cmd in tc ifstat iptables; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}[!] 错误: 找不到命令 $cmd${NC}"
            echo -e "${YELLOW}[*] 请安装必要的软件包:${NC}"
            echo "    - tc: 安装 iproute2 包"
            echo "    - ifstat: 安装 ifstat 包"
            echo "    - iptables: 安装 iptables 包"
            exit 1
        fi
    done
    echo -e "${GREEN}[+] 所有依赖已满足${NC}"
}

# 初始化流量控制
init_tc() {
    echo -e "${BLUE}[*] 初始化流量控制...${NC}"
    
    # 清除现有规则
    tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # 创建HTB qdisc
    tc qdisc add dev $INTERFACE root handle 1: htb default 10
    
    # 创建主要类别
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    
    # 创建受限带宽类别
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate ${MAX_BANDWIDTH}mbit ceil ${MAX_BANDWIDTH}mbit
    
    # 为受限带宽类添加SFQ队列规则以确保公平性
    tc qdisc add dev $INTERFACE parent 1:10 handle 10: sfq perturb 10
    
    echo -e "${GREEN}[+] 流量控制初始化完成，带宽限制为 ${MAX_BANDWIDTH}Mbps${NC}"
}

# 启用流量整形
enable_shaping() {
    local speed=$1  # 速度，单位Mbps
    echo -e "${YELLOW}[*] 启用流量整形，设置带宽上限为 ${speed}Mbps${NC}"
    
    # 更新类别带宽
    tc class change dev $INTERFACE parent 1:1 classid 1:10 htb rate ${speed}mbit ceil ${speed}mbit
    
    log_event "启用流量整形 - 设置带宽上限为 ${speed}Mbps"
}

# 完全解除限制
disable_shaping() {
    echo -e "${GREEN}[*] 解除流量整形限制${NC}"
    
    # 设置非常高的带宽限制（相当于不限制）
    tc class change dev $INTERFACE parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit
    
    log_event "解除流量整形限制"
}

# 暂停网络活动
pause_network() {
    echo -e "${RED}[*] 暂停所有网络活动 ${PAUSE_DURATION} 秒...${NC}"
    
    # 使用iptables暂时阻止所有出站流量
    iptables -A OUTPUT -j DROP
    
    log_event "暂停网络活动"
    
    sleep $PAUSE_DURATION
    
    # 恢复流量
    iptables -D OUTPUT -j DROP
    
    echo -e "${GREEN}[*] 恢复网络活动${NC}"
    log_event "恢复网络活动"
    
    # 重置计数器
    reset_counters
}

# 重置计数器
reset_counters() {
    # 重置计数文件
    echo "0" > /tmp/traffic_total
    echo "$(date +%s)" > /tmp/traffic_start_time
    echo "0" > /tmp/high_bandwidth_start

    log_event "重置流量计数器"
}

# 记录事件
log_event() {
    local message=$1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> $LOG_FILE
}

# 获取当前带宽使用情况 (Mbps)
get_current_bandwidth() {
    # 使用ifstat获取当前带宽
    ifstat -i "$INTERFACE" -b 1 1 | tail -1 | awk '{print $2}'
}

# 获取已用流量 (MB)
get_used_traffic() {
    if [ ! -f /tmp/traffic_total ]; then
        echo "0" > /tmp/traffic_total
    fi
    cat /tmp/traffic_total
}

# 更新已用流量
update_traffic() {
    local new_bytes=$1
    local current=$(get_used_traffic)
    echo $(echo "$current + $new_bytes" | bc) > /tmp/traffic_total
}

# 智能流量监控主函数
monitor_traffic() {
    echo -e "${BLUE}[*] 开始智能流量监控...${NC}"
    log_event "开始智能流量监控"
    
    # 初始化计数器
    reset_counters
    
    # 设置初始带宽
    enable_shaping $MAX_BANDWIDTH
    
    while true; do
        # 获取当前带宽 (Mbps)
        current_bw=$(get_current_bandwidth)
        
        # 计算此周期传输的流量 (MB)
        transferred_mb=$(echo "scale=2; $current_bw * $MONITOR_INTERVAL / 8" | bc)
        
        # 更新总流量计数器
        update_traffic $transferred_mb
        
        # 获取当前总流量
        total_traffic=$(get_used_traffic)
        
        # 显示状态
        echo -e "${BLUE}[*] 当前带宽: ${current_bw} Mbps, 已用流量: ${total_traffic} MB${NC}"
        
        # 检查是否接近连续数据限制
        if (( $(echo "$total_traffic > $MAX_CONTINUOUS_DATA * 0.9" | bc -l) )); then
            echo -e "${RED}[!] 警告: 接近连续数据限制 (5GB)${NC}"
            log_event "接近连续数据限制 (5GB) - 当前已用: ${total_traffic}MB"
            pause_network
            continue
        fi
        
        # 检查带宽是否超过阈值
        if (( $(echo "$current_bw > $MAX_BANDWIDTH * 0.9" | bc -l) )); then
            # 检查高带宽持续时间
            if [ ! -f /tmp/high_bandwidth_start ]; then
                echo "$(date +%s)" > /tmp/high_bandwidth_start
                echo -e "${YELLOW}[!] 检测到高带宽使用，开始计时...${NC}"
                log_event "检测到高带宽使用，开始计时"
            else
                start_time=$(cat /tmp/high_bandwidth_start)
                current_time=$(date +%s)
                duration=$((current_time - start_time))
                
                # 如果持续时间接近限制
                if [ $duration -gt $((BANDWIDTH_TIME_LIMIT * 4 / 5)) ]; then
                    echo -e "${RED}[!] 警告: 高带宽使用已持续 ${duration} 秒，接近限制 (${BANDWIDTH_TIME_LIMIT} 秒)${NC}"
                    log_event "高带宽使用持续时间接近限制 - ${duration}/${BANDWIDTH_TIME_LIMIT}秒"
                    pause_network
                    continue
                fi
                
                echo -e "${YELLOW}[!] 高带宽使用已持续 ${duration} 秒${NC}"
            fi
        else
            # 重置高带宽计时器
            if [ -f /tmp/high_bandwidth_start ]; then
                echo -e "${GREEN}[+] 带宽恢复正常，重置高带宽计时器${NC}"
                log_event "带宽恢复正常，重置高带宽计时器"
                echo "0" > /tmp/high_bandwidth_start
            fi
        fi
        
        # 动态调整带宽避免触发限制
        if (( $(echo "$current_bw > $MAX_BANDWIDTH * 0.95" | bc -l) )); then
            new_limit=$(echo "$MAX_BANDWIDTH * 0.85" | bc)
            echo -e "${YELLOW}[!] 带宽接近限制，降低上限至 ${new_limit}Mbps${NC}"
            enable_shaping $new_limit
        elif (( $(echo "$current_bw < $MAX_BANDWIDTH * 0.7" | bc -l) )); then
            echo -e "${GREEN}[+] 带宽使用适中，恢复正常上限${NC}"
            enable_shaping $MAX_BANDWIDTH
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# 清理函数
cleanup() {
    echo -e "${YELLOW}[*] 正在清理...${NC}"
    
    # 删除流量控制规则
    tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # 确保没有遗留的iptables规则
    iptables -D OUTPUT -j DROP 2>/dev/null
    
    # 删除临时文件
    rm -f /tmp/traffic_total /tmp/traffic_start_time /tmp/high_bandwidth_start
    
    echo -e "${GREEN}[+] 清理完成${NC}"
    log_event "程序正常退出，清理完成"
    
    exit 0
}

# 设置清理陷阱
trap cleanup EXIT INT TERM

# 主程序
main() {
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}      系统级智能流量控制方案        ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${YELLOW}限速触发条件:${NC}"
    echo -e "${YELLOW}1. 连续下载超过5GB流量${NC}"
    echo -e "${YELLOW}2. 占用带宽超过50Mbps达5分钟以上${NC}"
    echo -e "${GREEN}=====================================${NC}"
    
    # 检查是否为root用户
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[!] 错误: 此脚本需要root权限运行${NC}"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 初始化流量整形
    init_tc
    
    # 开始监控
    monitor_traffic
}

# 运行主程序
main
