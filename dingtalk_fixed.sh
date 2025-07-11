#!/bin/bash
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取调用者脚本的路径
get_caller_path() {
    # 方法1: 尝试从BASH_SOURCE获取调用栈
    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        # 如果有调用栈，获取调用者脚本路径
        caller_script="${BASH_SOURCE[1]}"
        if [ -f "$caller_script" ] && [ "$caller_script" != "$0" ]; then
            echo "$(realpath "$caller_script")"
            return
        fi
    fi
    
    # 方法2: 通过父进程分析
    parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')  # 去除空格
    
    if [ -n "$parent_pid" ] && [ "$parent_pid" != "1" ]; then
        # 尝试获取父进程的命令行
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)
        else
            # Linux
            parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)
        fi
        
        if [ -n "$parent_cmd" ]; then
            # 从命令行中提取脚本路径
            # 匹配模式如: bash script.sh, ./script.sh, /path/script.sh
            script_path=$(echo "$parent_cmd" | grep -oE '(/[^ ]*\.sh|\.\/[^ ]*\.sh|[^ ]*\.sh)' | head -1)
            
            if [ -n "$script_path" ] && [ -f "$script_path" ]; then
                echo "$(realpath "$script_path")"
                return
            fi
        fi
    fi
    
    # 方法3: 检查命令行参数中是否有脚本路径
    # 这个方法适用于直接调用的情况
    for arg in "$@"; do
        if [[ "$arg" =~ \.sh$ ]] && [ -f "$arg" ]; then
            echo "$(realpath "$arg")"
            return
        fi
    done
    
    # 方法4: 尝试从环境变量获取
    if [ -n "$CALLER_SCRIPT" ]; then
        echo "$CALLER_SCRIPT"
        return
    fi
    
    # 最后的fallback
    echo "$(pwd) (终端直接执行)"
}

# 获取调用信息
caller_info=$(get_caller_path "$@")
hostname=$(hostname)

# 构建消息
msg="${hostname}:\n${caller_info}:\n$1"

# 发送到钉钉
curl -s "$DINGTALK_WEBHOOK" \
     -H 'Content-Type: application/json' \
     -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg\"}}"

echo "消息已发送: $msg"