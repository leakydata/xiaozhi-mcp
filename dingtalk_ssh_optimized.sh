#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# SSH环境优化的调用者检测
get_caller_path() {
    local debug="${DEBUG_CALLER:-0}"
    
    # 调试函数
    debug_log() { [ "$debug" = "1" ] && echo "DEBUG: $*" >&2; }
    
    debug_log "=== 开始调用者检测 ==="
    
    # 方法1: 检查BASH_SOURCE（最直接的方法）
    debug_log "方法1: 检查BASH_SOURCE数组"
    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        for i in "${!BASH_SOURCE[@]}"; do
            debug_log "BASH_SOURCE[$i]: ${BASH_SOURCE[$i]}"
            local source_file="${BASH_SOURCE[$i]}"
            if [ -f "$source_file" ] && [ "$source_file" != "$0" ]; then
                debug_log "找到调用者(BASH_SOURCE): $source_file"
                realpath "$source_file" 2>/dev/null || echo "$source_file"
                return
            fi
        done
    fi
    
    # 方法2: 检查当前shell的执行脚本
    debug_log "方法2: 检查shell执行环境"
    
    # 获取当前shell进程的信息
    local shell_pid=$$
    debug_log "当前shell PID: $shell_pid"
    
    # 检查/proc/PID/cmdline获取完整命令行
    if [ -r "/proc/$shell_pid/cmdline" ]; then
        local cmdline=$(tr '\0' ' ' < "/proc/$shell_pid/cmdline" 2>/dev/null)
        debug_log "当前进程cmdline: $cmdline"
        
        # 从cmdline中提取脚本路径
        local script_from_cmdline=$(extract_script_path "$cmdline")
        if [ -n "$script_from_cmdline" ] && [ -f "$script_from_cmdline" ]; then
            debug_log "找到调用者(cmdline): $script_from_cmdline"
            realpath "$script_from_cmdline" 2>/dev/null || echo "$script_from_cmdline"
            return
        fi
    fi
    
    # 方法3: 分析$0变量和执行环境
    debug_log "方法3: 分析执行环境"
    debug_log "\$0 = $0"
    
    # 如果$0是脚本文件路径
    if [ -f "$0" ] && [[ "$0" == *.sh ]]; then
        debug_log "找到调用者(\$0): $0"
        realpath "$0" 2>/dev/null || echo "$0"
        return
    fi
    
    # 方法4: 检查当前目录的脚本执行情况
    debug_log "方法4: 当前目录分析"
    debug_log "当前工作目录: $(pwd)"
    
    # 查找当前目录中最近执行/修改的脚本
    local recent_scripts=$(find "$(pwd)" -maxdepth 1 -name "*.sh" -type f -executable -mmin -5 2>/dev/null)
    debug_log "最近5分钟内修改的脚本: $recent_scripts"
    
    if [ -n "$recent_scripts" ]; then
        # 获取最新的脚本
        local latest_script=$(echo "$recent_scripts" | xargs ls -t 2>/dev/null | head -1)
        if [ -f "$latest_script" ]; then
            debug_log "找到调用者(推断最新): $latest_script"
            realpath "$latest_script" 2>/dev/null || echo "$latest_script"
            return
        fi
    fi
    
    # 方法5: 检查history命令（SSH环境特有）
    debug_log "方法5: SSH环境检查"
    
    # 尝试从bash历史中获取最近执行的脚本
    if command -v history >/dev/null 2>&1; then
        local last_command=$(history 2 2>/dev/null | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
        debug_log "最近执行的命令: $last_command"
        
        # 从历史命令中提取脚本路径
        local script_from_history=$(extract_script_path "$last_command")
        if [ -n "$script_from_history" ] && [ -f "$script_from_history" ]; then
            debug_log "找到调用者(history): $script_from_history"
            realpath "$script_from_history" 2>/dev/null || echo "$script_from_history"
            return
        fi
    fi
    
    # 方法6: 深度进程树分析（针对SSH环境优化）
    debug_log "方法6: 深度进程树分析"
    local pid=$$
    
    for depth in {0..5}; do
        local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        debug_log "深度$depth: PID=$pid, PPID=$ppid"
        
        [ -z "$ppid" ] || [ "$ppid" = "1" ] && break
        
        # 获取进程信息
        local proc_info=$(ps -p "$ppid" -o args= 2>/dev/null)
        debug_log "进程命令: $proc_info"
        
        # 跳过SSH相关进程，继续向上查找
        if [[ "$proc_info" == *"sshd"* ]] || [[ "$proc_info" == "-bash" ]]; then
            debug_log "跳过SSH/bash进程，继续向上查找"
            pid="$ppid"
            continue
        fi
        
        # 提取脚本路径
        local script_path=$(extract_script_path "$proc_info")
        if [ -n "$script_path" ] && [ -f "$script_path" ]; then
            debug_log "找到调用者(进程树): $script_path"
            realpath "$script_path" 2>/dev/null || echo "$script_path"
            return
        fi
        
        pid="$ppid"
    done
    
    # 方法7: 环境变量检查
    debug_log "方法7: 环境变量检查"
    
    # 检查常见的脚本相关环境变量
    for var_name in SCRIPT_NAME BASH_SOURCE PWD _; do
        local var_value=$(eval echo "\$$var_name" 2>/dev/null)
        debug_log "环境变量 $var_name: $var_value"
        
        if [[ "$var_value" == *.sh ]] && [ -f "$var_value" ]; then
            debug_log "找到调用者(环境变量 $var_name): $var_value"
            realpath "$var_value" 2>/dev/null || echo "$var_value"
            return
        fi
    done
    
    # 最后的fallback：返回当前目录和基本信息
    debug_log "所有方法都失败，返回基本信息"
    
    # 构建详细的环境信息
    local pwd_info="$(pwd)"
    local user_info="$(whoami)@$(hostname)"
    local ssh_info=""
    
    # 检查SSH连接信息
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
        ssh_info=" (SSH: ${SSH_CLIENT%% *})"
    fi
    
    echo "${pwd_info} [${user_info}${ssh_info}]"
}

# 修复的脚本路径提取函数
extract_script_path() {
    local cmd="$1"
    debug_log() { [ "${DEBUG_CALLER:-0}" = "1" ] && echo "DEBUG: $*" >&2; }
    
    debug_log "提取脚本路径: $cmd"
    
    # 清理命令行（去除重定向、管道等）
    local clean_cmd=$(echo "$cmd" | sed 's/[|&;].*$//' | sed 's/[<>].*$//')
    debug_log "清理后命令: $clean_cmd"
    
    # 多种提取模式（修复sed语法）
    local patterns=(
        # bash script.sh
        's/.*bash[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/'
        # sh script.sh  
        's/.*sh[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/'
        # ./script.sh
        's/.*\(\./[^[:space:]]*\.sh\).*/\1/'
        # /path/script.sh
        's|.*\(/[^[:space:]]*\.sh\).*|\1|'
        # script.sh (简单名称)
        's/.*[[:space:]]\([^[:space:]/]*\.sh\)[[:space:]].*/\1/'
    )
    
    for pattern in "${patterns[@]}"; do
        local candidate=$(echo "$clean_cmd" | sed -n "${pattern}p" 2>/dev/null)
        debug_log "模式 '$pattern' 结果: '$candidate'"
        
        if [ -n "$candidate" ]; then
            # 验证文件存在
            if [ -f "$candidate" ]; then
                echo "$candidate"
                return
            fi
            
            # 尝试相对路径
            if [[ "$candidate" == ./* ]] || [[ "$candidate" != /* ]]; then
                local full_path="$(pwd)/$candidate"
                if [ -f "$full_path" ]; then
                    echo "$full_path"
                    return
                fi
            fi
            
            # 尝试PATH查找
            if command -v "$candidate" >/dev/null 2>&1; then
                which "$candidate" 2>/dev/null
                return
            fi
        fi
    done
}

# 发送钉钉消息
send_dingtalk_message() {
    local message="$1"
    local response

    response=$(curl -s "$DINGTALK_WEBHOOK" \
                   -H 'Content-Type: application/json' \
                   -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$message\"}}" \
                   2>/dev/null)

    if echo "$response" | grep -q '"errcode":0'; then
        echo "✅ 消息发送成功"
        return 0
    else
        echo "❌ 消息发送失败: $response"
        return 1
    fi
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <消息内容>"
        echo "示例: $0 '服务器状态正常'"
        echo ""
        echo "调试: DEBUG_CALLER=1 $0 '消息'"
        exit 1
    fi

    local hostname=$(hostname)
    local caller_path=$(get_caller_path)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message_content="$1"

    local full_message="📊 系统通知

🖥️ 主机: $hostname
⏰ 时间: $timestamp
📍 调用者: $caller_path
💬 消息: $message_content"

    echo "=== 消息详情 ==="
    echo "主机: $hostname"
    echo "时间: $timestamp"
    echo "调用者: $caller_path"
    echo "消息: $message_content"
    echo "================"

    send_dingtalk_message "$full_message"
}

main "$@"