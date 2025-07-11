#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 简化但可靠的调用者检测（专门针对SSH环境）
get_caller_path() {
    local debug="${DEBUG_CALLER:-0}"
    debug_log() { [ "$debug" = "1" ] && echo "DEBUG: $*" >&2; }
    
    debug_log "=== SSH环境调用者检测 ==="
    
    # 方法1: 检查$0（最简单可靠）
    debug_log "方法1: 检查 \$0 变量"
    debug_log "\$0 = '$0'"
    
    if [ -f "$0" ] && [[ "$0" == *.sh ]]; then
        debug_log "找到脚本(\$0): $0"
        if [[ "$0" == /* ]]; then
            # 绝对路径
            echo "$0"
        else
            # 相对路径转绝对路径
            echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        fi
        return
    fi
    
    # 方法2: 当前目录智能推断
    debug_log "方法2: 当前目录推断"
    debug_log "PWD: $(pwd)"
    
    # 查找当前目录中的.sh文件
    local sh_files=$(find "$(pwd)" -maxdepth 1 -name "*.sh" -type f 2>/dev/null)
    debug_log "发现的.sh文件: $sh_files"
    
    if [ -n "$sh_files" ]; then
        # 如果只有一个.sh文件，很可能就是调用者
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
    
    # 方法3: 检查history（如果可用）
    debug_log "方法3: 检查执行历史"
    
    if command -v history >/dev/null 2>&1; then
        # 获取最近几条命令
        local recent_commands=$(history 5 2>/dev/null | tail -3)
        debug_log "最近命令: $recent_commands"
        
        # 从历史中找.sh文件
        local script_from_hist=$(echo "$recent_commands" | grep -o '[^[:space:]]*\.sh' | head -1)
        if [ -n "$script_from_hist" ] && [ -f "$script_from_hist" ]; then
            debug_log "从历史找到: $script_from_hist"
            if [[ "$script_from_hist" == /* ]]; then
                echo "$script_from_hist"
            else
                echo "$(pwd)/$script_from_hist"
            fi
            return
        fi
    fi
    
    # 方法4: 环境变量分析
    debug_log "方法4: 环境变量分析"
    
    # 检查_ 变量（通常包含最后执行的命令）
    if [ -n "$_" ]; then
        debug_log "_ 变量: $_"
        if [[ "$_" == *.sh ]] && [ -f "$_" ]; then
            debug_log "从_变量找到: $_"
            echo "$_"
            return
        fi
    fi
    
    # 方法5: 根据当前目录名推断
    debug_log "方法5: 目录名推断"
    
    local current_dir=$(basename "$(pwd)")
    debug_log "当前目录名: $current_dir"
    
    # 查找与目录名相关的脚本
    local dir_script="$(pwd)/${current_dir}.sh"
    if [ -f "$dir_script" ]; then
        debug_log "找到目录同名脚本: $dir_script"
        echo "$dir_script"
        return
    fi
    
    # 查找常见的脚本名
    local common_names=("export.sh" "backup.sh" "main.sh" "run.sh" "start.sh")
    for name in "${common_names[@]}"; do
        local common_script="$(pwd)/$name"
        if [ -f "$common_script" ]; then
            debug_log "找到常见脚本: $common_script"
            echo "$common_script"
            return
        fi
    done
    
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