#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取调用者脚本的路径（生产版本）
get_caller_path() {
    local caller_path=""

    # 方法1: 优先使用环境变量（最可靠）
    if [ -n "${CALLER_SCRIPT:-}" ]; then
        echo "$CALLER_SCRIPT"
        return
    fi

    # 方法2: 通过BASH_SOURCE获取调用栈
    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        caller_path="${BASH_SOURCE[1]}"
        if [ -f "$caller_path" ] && [ "$caller_path" != "$0" ]; then
            realpath "$caller_path" 2>/dev/null || echo "$caller_path"
            return
        fi
    fi

    # 方法3: 分析父进程命令行（增强版）
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')

    if [ -n "$parent_pid" ] && [ "$parent_pid" != "1" ]; then
        local parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)

        if [ -n "$parent_cmd" ]; then
            # 多种脚本路径提取模式
            local script_candidates=()
            
            # 匹配各种脚本格式
            mapfile -t candidates < <(echo "$parent_cmd" | grep -oE '[^[:space:]]+\.(sh|bash|py|pl|rb)\b')
            script_candidates+=("${candidates[@]}")
            
            # 处理 "bash /path/script.sh" 格式
            local bash_script=$(echo "$parent_cmd" | sed -n 's/.*bash[[:space:]]\+\([^[:space:]]*\.(sh|bash)\).*/\1/p')
            [ -n "$bash_script" ] && script_candidates+=("$bash_script")
            
            # 处理 "sh /path/script.sh" 格式  
            local sh_script=$(echo "$parent_cmd" | sed -n 's/.*sh[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/p')
            [ -n "$sh_script" ] && script_candidates+=("$sh_script")

            # 验证候选路径
            for candidate in "${script_candidates[@]}"; do
                # 直接检查文件
                if [ -f "$candidate" ] && [ -r "$candidate" ]; then
                    realpath "$candidate" 2>/dev/null || echo "$candidate"
                    return
                fi
                
                # 相对路径检查
                if [[ "$candidate" == ./* ]] || [[ "$candidate" != /* ]]; then
                    local full_path="$(pwd)/$candidate"
                    if [ -f "$full_path" ] && [ -r "$full_path" ]; then
                        realpath "$full_path" 2>/dev/null || echo "$full_path"
                        return
                    fi
                fi
                
                # PATH中查找
                if command -v "$candidate" >/dev/null 2>&1; then
                    which "$candidate" 2>/dev/null
                    return
                fi
            done
        fi

        # 获取父进程可执行文件路径
        if [ -r "/proc/$parent_pid/exe" ]; then
            local parent_exe=$(readlink "/proc/$parent_pid/exe" 2>/dev/null)
            if [ -n "$parent_exe" ] && [ "$parent_exe" != "/usr/bin/bash" ] && [ "$parent_exe" != "/bin/bash" ]; then
                echo "$parent_exe"
                return
            fi
        fi
        
        # 返回进程信息
        local parent_name=$(ps -o comm= -p "$parent_pid" 2>/dev/null)
        if [ -n "$parent_name" ]; then
            echo "进程: $parent_name (PID: $parent_pid)"
            return
        fi
    fi

    # 最后的fallback
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
        echo ""
        echo "在调用脚本中设置环境变量可确保路径准确:"
        echo "  export CALLER_SCRIPT=\"\$(realpath \"\$0\")\""
        echo "  $0 '消息内容'"
        exit 1
    fi

    # 获取信息
    local hostname=$(hostname)
    local caller_path=$(get_caller_path)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message_content="$1"

    # 构建消息
    local full_message="📊 系统通知

🖥️ 主机: $hostname
⏰ 时间: $timestamp
📍 调用者: $caller_path
💬 消息: $message_content"

    # 输出调试信息
    echo "=== 消息详情 ==="
    echo "主机: $hostname"
    echo "时间: $timestamp"
    echo "调用者: $caller_path"
    echo "消息: $message_content"
    echo "================"

    # 发送消息
    send_dingtalk_message "$full_message"
}

# 执行主函数
main "$@"