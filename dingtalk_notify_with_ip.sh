#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取公网IP地址
get_public_ip() {
    local ip=""
    local timeout=3
    
    # 多个IP查询服务，提高成功率
    local services=(
        "ipinfo.io/ip"
        "ifconfig.me"
        "checkip.amazonaws.com"
        "ipecho.net/plain"
        "icanhazip.com"
    )
    
    for service in "${services[@]}"; do
        echo "尝试从 $service 获取IP..." >&2
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
    # 优先获取默认路由的网卡IP
    local private_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    
    if [ -z "$private_ip" ]; then
        # 备选方案：获取第一个非lo网卡的IP
        private_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -z "$private_ip" ]; then
        # 最后备选：使用ifconfig
        private_ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d: -f2)
    fi
    
    echo "${private_ip:-未知}"
}

# 获取调用者脚本的路径
get_caller_path() {
    local caller_path=""
    
    # 方法1: 通过BASH_SOURCE获取调用栈（最可靠）
    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        caller_path="${BASH_SOURCE[1]}"
        if [ -f "$caller_path" ] && [ "$caller_path" != "$0" ]; then
            realpath "$caller_path" 2>/dev/null || echo "$caller_path"
            return
        fi
    fi
    
    # 方法2: 分析父进程命令行
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    
    if [ -n "$parent_pid" ] && [ "$parent_pid" != "1" ]; then
        local parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)
        
        if [ -n "$parent_cmd" ]; then
            # 从命令行中提取脚本路径
            # 匹配: bash script.sh, ./script.sh, /path/script.sh
            local script_path=$(echo "$parent_cmd" | grep -oE '\S*\.sh\b' | head -1)
            
            # 验证脚本文件存在且可读
            if [ -n "$script_path" ] && [ -f "$script_path" ] && [ -r "$script_path" ]; then
                realpath "$script_path" 2>/dev/null || echo "$script_path"
                return
            fi
        fi
        
        # 如果找不到脚本，返回父进程信息
        local parent_name=$(ps -o comm= -p "$parent_pid" 2>/dev/null)
        if [ -n "$parent_name" ]; then
            echo "进程: $parent_name (PID: $parent_pid)"
            return
        fi
    fi
    
    # 方法3: 环境变量方式（可由调用脚本设置）
    if [ -n "${CALLER_SCRIPT:-}" ]; then
        echo "$CALLER_SCRIPT"
        return
    fi
    
    # 方法4: 检查当前工作目录和执行方式
    if [ -t 0 ]; then
        echo "$(pwd) (交互式终端)"
    else
        echo "$(pwd) (非交互式执行)"
    fi
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
        echo "✅ 消息发送成功"
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
        echo "示例: $0 '服务器状态正常'"
        exit 1
    fi
    
    echo "🔍 正在收集系统信息..."
    
    # 获取信息
    local hostname=$(hostname)
    local caller_path=$(get_caller_path)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message_content="$1"
    
    # 获取IP信息
    echo "📡 获取网络信息..."
    local public_ip=$(get_public_ip)
    local private_ip=$(get_private_ip)
    
    # 构建消息
    local full_message="📊 系统通知

🖥️ 主机: $hostname
⏰ 时间: $timestamp  
📍 调用者: $caller_path
🌐 公网IP: $public_ip
🏠 内网IP: $private_ip
💬 消息: $message_content"
    
    # 输出调试信息
    echo "=== 消息详情 ==="
    echo "主机: $hostname"
    echo "时间: $timestamp"
    echo "调用者: $caller_path"
    echo "公网IP: $public_ip"
    echo "内网IP: $private_ip"
    echo "消息: $message_content"
    echo "================"
    
    # 发送消息
    send_dingtalk_message "$full_message"
}

# 执行主函数
main "$@"