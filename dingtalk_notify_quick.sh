#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 环境变量配置
# SKIP_PUBLIC_IP=1 跳过公网IP获取（加快速度）
# SKIP_PRIVATE_IP=1 跳过内网IP获取
# SIMPLE_MODE=1 简化输出格式

# 获取公网IP地址
get_public_ip() {
    # 如果设置了跳过标志，直接返回
    if [ "${SKIP_PUBLIC_IP:-}" = "1" ]; then
        echo "跳过"
        return
    fi
    
    local ip=""
    local timeout=2
    
    # 快速IP查询服务
    local services=(
        "ipinfo.io/ip"
        "ifconfig.me"
        "icanhazip.com"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -s --connect-timeout $timeout --max-time $timeout "$service" 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
        
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    
    echo "获取失败"
    return 1
}

# 获取内网IP地址
get_private_ip() {
    # 如果设置了跳过标志，直接返回
    if [ "${SKIP_PRIVATE_IP:-}" = "1" ]; then
        echo "跳过"
        return
    fi
    
    # 快速获取默认路由的网卡IP
    local private_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    
    if [ -z "$private_ip" ]; then
        private_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    echo "${private_ip:-未知}"
}

# 获取调用者脚本的路径（简化版）
get_caller_path() {
    # 优先使用BASH_SOURCE
    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        local caller_script="${BASH_SOURCE[1]}"
        if [ -f "$caller_script" ] && [ "$caller_script" != "$0" ]; then
            basename "$caller_script" 2>/dev/null || echo "$caller_script"
            return
        fi
    fi
    
    # 简化的父进程检测
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    if [ -n "$parent_pid" ] && [ "$parent_pid" != "1" ]; then
        local parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)
        local script_path=$(echo "$parent_cmd" | grep -oE '\S*\.sh\b' | head -1)
        
        if [ -n "$script_path" ] && [ -f "$script_path" ]; then
            basename "$script_path" 2>/dev/null || echo "$script_path"
            return
        fi
    fi
    
    echo "终端"
}

# 发送钉钉消息的函数
send_dingtalk_message() {
    local message="$1"
    local response
    
    response=$(curl -s "$DINGTALK_WEBHOOK" \
                   -H 'Content-Type: application/json' \
                   -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$message\"}}" \
                   2>/dev/null)
    
    # 检查发送结果
    if echo "$response" | grep -q '"errcode":0'; then
        [ "${SIMPLE_MODE:-}" != "1" ] && echo "✅ 消息发送成功"
        return 0
    else
        echo "❌ 消息发送失败: $response"
        return 1
    fi
}

# 主逻辑
main() {
    # 检查参数
    if [ $# -eq 0 ]; then
        echo "用法: $0 <消息内容>"
        echo ""
        echo "环境变量选项:"
        echo "  SKIP_PUBLIC_IP=1  跳过公网IP获取（加快速度）"
        echo "  SKIP_PRIVATE_IP=1 跳过内网IP获取"
        echo "  SIMPLE_MODE=1     简化输出模式"
        echo ""
        echo "示例:"
        echo "  $0 '服务器状态正常'"
        echo "  SKIP_PUBLIC_IP=1 $0 '快速通知'"
        echo "  SIMPLE_MODE=1 $0 '简单通知'"
        exit 1
    fi
    
    # 获取基础信息
    local hostname=$(hostname)
    local caller_path=$(get_caller_path)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message_content="$1"
    
    # 根据模式获取IP信息
    local public_ip=""
    local private_ip=""
    
    if [ "${SIMPLE_MODE:-}" != "1" ]; then
        [ "${SKIP_PUBLIC_IP:-}" != "1" ] && public_ip=$(get_public_ip)
        [ "${SKIP_PRIVATE_IP:-}" != "1" ] && private_ip=$(get_private_ip)
    fi
    
    # 构建消息
    local full_message
    
    if [ "${SIMPLE_MODE:-}" = "1" ]; then
        # 简化模式
        full_message="📱 ${hostname} | ${caller_path}
⏰ ${timestamp}
💬 ${message_content}"
    else
        # 完整模式
        full_message="📊 系统通知

🖥️ 主机: $hostname
⏰ 时间: $timestamp  
📍 调用者: $caller_path"

        # 添加IP信息（如果获取了的话）
        [ -n "$public_ip" ] && full_message="$full_message
🌐 公网IP: $public_ip"
        [ -n "$private_ip" ] && full_message="$full_message
🏠 内网IP: $private_ip"
        
        full_message="$full_message
💬 消息: $message_content"
    fi
    
    # 输出调试信息（非简化模式）
    if [ "${SIMPLE_MODE:-}" != "1" ]; then
        echo "=== 消息详情 ==="
        echo "主机: $hostname"
        echo "时间: $timestamp"
        echo "调用者: $caller_path"
        [ -n "$public_ip" ] && echo "公网IP: $public_ip"
        [ -n "$private_ip" ] && echo "内网IP: $private_ip"
        echo "消息: $message_content"
        echo "================"
    fi
    
    # 发送消息
    send_dingtalk_message "$full_message"
}

# 执行主函数
main "$@"