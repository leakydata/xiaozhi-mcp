#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 简化但可靠的调用者检测（专门针对SSH环境）
get_caller_path() {
    local debug="${DEBUG_CALLER:-0}"
    debug_log() { [ "$debug" = "1" ] && echo "DEBUG: $*" >&2; }
    
    debug_log "=== SSH环境调用者检测 ==="
    
    # 方法1: 进程树分析 - 找到真正的调用脚本
    debug_log "方法1: 进程树分析"
    
    local current_pid=$$
    debug_log "当前PID: $current_pid"
    
    # 向上追溯进程树，跳过自己和bash进程
    local pid=$current_pid
    local found_script=""
    
    for i in {1..5}; do
        # 获取父进程PID
        local parent_pid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        debug_log "检查进程 $pid，父进程: $parent_pid"
        
        if [ -z "$parent_pid" ] || [ "$parent_pid" = "1" ]; then
            debug_log "到达进程树顶端"
            break
        fi
        
        # 获取父进程的命令行
        local parent_cmd=$(ps -o cmd= -p $parent_pid 2>/dev/null)
        debug_log "父进程命令: $parent_cmd"
        
        # 跳过bash, sh, sshd等系统进程
        if [[ "$parent_cmd" =~ ^-?bash$|^-?sh$|sshd|^su ]]; then
            debug_log "跳过系统进程: $parent_cmd"
            pid=$parent_pid
            continue
        fi
        
        # 检查是否是脚本调用
        if [[ "$parent_cmd" =~ \.sh ]] || [[ "$parent_cmd" =~ bash.*\.sh ]] || [[ "$parent_cmd" =~ sh.*\.sh ]]; then
            # 提取脚本路径
            local script_path=$(echo "$parent_cmd" | grep -o '[^[:space:]]*\.sh' | head -1)
            debug_log "从命令行提取脚本: $script_path"
            
            # 验证脚本是否存在
            if [ -f "$script_path" ]; then
                found_script="$script_path"
                debug_log "找到调用脚本: $found_script"
                break
            elif [ -f "./$script_path" ]; then
                found_script="$(pwd)/$script_path"
                debug_log "找到相对路径脚本: $found_script"
                break
            fi
        fi
        
        pid=$parent_pid
    done
    
    # 如果找到了脚本，返回绝对路径
    if [ -n "$found_script" ]; then
        if [[ "$found_script" == /* ]]; then
            echo "$found_script"
        else
            echo "$(cd "$(dirname "$found_script")" && pwd)/$(basename "$found_script")"
        fi
        return
    fi
    
    # 方法2: 检查$0（但要确保不是自己）
    debug_log "方法2: 检查 \$0 变量"
    debug_log "\$0 = '$0'"
    
    # 确保$0不是当前脚本本身
    local script_name=$(basename "$0")
    if [ -f "$0" ] && [[ "$0" == *.sh ]] && [[ "$script_name" != "todingding.sh" ]] && [[ "$script_name" != "dingtalk_ssh_simple.sh" ]]; then
        debug_log "找到脚本(\$0): $0"
        if [[ "$0" == /* ]]; then
            echo "$0"
        else
            echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        fi
        return
    fi
    
    # 方法3: 当前目录智能推断
    debug_log "方法3: 当前目录推断"
    debug_log "PWD: $(pwd)"
    
    # 查找当前目录中的.sh文件，排除钉钉通知脚本
    local sh_files=$(find "$(pwd)" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | grep -v todingding | grep -v dingtalk)
    debug_log "发现的.sh文件: $sh_files"
    
    if [ -n "$sh_files" ]; then
        local count=$(echo "$sh_files" | wc -l)
        if [ "$count" -eq 1 ]; then
            debug_log "只有一个.sh文件，可能是调用者: $sh_files"
            echo "$sh_files"
            return
        fi
        
        # 如果有多个，选择最近修改的
        local latest=$(echo "$sh_files" | xargs ls -t 2>/dev/null | head -1)
        if [ -f "$latest" ]; then
            debug_log "选择最近修改的: $latest"
            echo "$latest"
            return
        fi
    fi
    
    # 方法4: 检查activate子目录（根据用户的路径结构）
    debug_log "方法4: 检查activate子目录"
    
    if [ -d "./activate" ]; then
        local activate_scripts=$(find "./activate" -name "*.sh" -type f 2>/dev/null)
        debug_log "activate目录中的脚本: $activate_scripts"
        
        if [ -n "$activate_scripts" ]; then
            local latest_activate=$(echo "$activate_scripts" | xargs ls -t 2>/dev/null | head -1)
            if [ -f "$latest_activate" ]; then
                debug_log "找到activate脚本: $latest_activate"
                echo "$(cd "$(dirname "$latest_activate")" && pwd)/$(basename "$latest_activate")"
                return
            fi
        fi
    fi
    
    # 方法5: 环境变量和历史分析
    debug_log "方法5: 环境变量分析"
    
    # 检查_ 变量（通常包含最后执行的命令）
    if [ -n "$_" ]; then
        debug_log "_ 变量: $_"
        if [[ "$_" == *.sh ]] && [ -f "$_" ] && [[ "$_" != *"todingding"* ]]; then
            debug_log "从_变量找到: $_"
            echo "$_"
            return
        fi
    fi
    
    # 最终fallback: 返回详细的环境信息
    debug_log "所有方法失败，返回环境信息"
    
    local env_info="$(pwd)"
    local user_host="$(whoami)@$(hostname)"
    
    # SSH信息
    if [ -n "$SSH_CLIENT" ]; then
        local ssh_from="${SSH_CLIENT%% *}"
        env_info="$env_info [$user_host via SSH from $ssh_from]"
    else
        env_info="$env_info [$user_host]"
    fi
    
    echo "$env_info"
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