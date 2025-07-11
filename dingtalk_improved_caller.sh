#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取调用者脚本的路径（增强版）
get_caller_path() {
    local caller_path=""
    local debug_mode="${DEBUG_CALLER:-0}"

    # 调试输出函数
    debug_echo() {
        [ "$debug_mode" = "1" ] && echo "DEBUG: $*" >&2
    }

    # 方法1: 通过BASH_SOURCE获取调用栈（最可靠）
    debug_echo "方法1: 检查BASH_SOURCE数组"
    debug_echo "BASH_SOURCE数组长度: ${#BASH_SOURCE[@]}"
    for i in "${!BASH_SOURCE[@]}"; do
        debug_echo "BASH_SOURCE[$i]: ${BASH_SOURCE[$i]}"
    done

    if [ "${#BASH_SOURCE[@]}" -gt 1 ]; then
        caller_path="${BASH_SOURCE[1]}"
        if [ -f "$caller_path" ] && [ "$caller_path" != "$0" ]; then
            debug_echo "方法1成功: $caller_path"
            realpath "$caller_path" 2>/dev/null || echo "$caller_path"
            return
        fi
    fi

    # 方法2: 分析父进程命令行（增强版）
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    debug_echo "方法2: 分析父进程 PID: $parent_pid"

    if [ -n "$parent_pid" ] && [ "$parent_pid" != "1" ]; then
        local parent_cmd=$(ps -o args= -p "$parent_pid" 2>/dev/null)
        debug_echo "父进程完整命令: $parent_cmd"

        if [ -n "$parent_cmd" ]; then
            # 增强的脚本路径提取
            local script_candidates=()
            
            # 提取可能的脚本路径（多种模式）
            # 1. 匹配 .sh 结尾的文件
            while IFS= read -r candidate; do
                [ -n "$candidate" ] && script_candidates+=("$candidate")
            done < <(echo "$parent_cmd" | grep -oE '[^[:space:]]+\.sh\b')
            
            # 2. 匹配绝对路径格式的脚本
            while IFS= read -r candidate; do
                [ -n "$candidate" ] && script_candidates+=("$candidate")
            done < <(echo "$parent_cmd" | grep -oE '/[^[:space:]]*\.(sh|bash|py|pl|rb)\b')
            
            # 3. 匹配相对路径格式的脚本
            while IFS= read -r candidate; do
                [ -n "$candidate" ] && script_candidates+=("$candidate")
            done < <(echo "$parent_cmd" | grep -oE '\./[^[:space:]]*\.(sh|bash|py|pl|rb)\b')
            
            # 4. 匹配简单文件名（在PATH中）
            while IFS= read -r candidate; do
                [ -n "$candidate" ] && script_candidates+=("$candidate")
            done < <(echo "$parent_cmd" | grep -oE '[^[:space:]/]+\.(sh|bash|py|pl|rb)\b')

            debug_echo "发现的脚本候选路径: ${script_candidates[*]}"

            # 验证候选路径
            for candidate in "${script_candidates[@]}"; do
                debug_echo "检验候选路径: $candidate"
                
                # 直接检查文件是否存在
                if [ -f "$candidate" ] && [ -r "$candidate" ]; then
                    debug_echo "方法2成功(直接): $candidate"
                    realpath "$candidate" 2>/dev/null || echo "$candidate"
                    return
                fi
                
                # 如果是相对路径，尝试从当前目录查找
                if [[ "$candidate" == ./* ]] || [[ "$candidate" != /* ]]; then
                    local full_path="$(pwd)/$candidate"
                    if [ -f "$full_path" ] && [ -r "$full_path" ]; then
                        debug_echo "方法2成功(相对路径): $full_path"
                        realpath "$full_path" 2>/dev/null || echo "$full_path"
                        return
                    fi
                fi
                
                # 尝试在PATH中查找
                if command -v "$candidate" >/dev/null 2>&1; then
                    local which_result=$(which "$candidate" 2>/dev/null)
                    if [ -n "$which_result" ] && [ -f "$which_result" ]; then
                        debug_echo "方法2成功(PATH): $which_result"
                        echo "$which_result"
                        return
                    fi
                fi
            done

            # 高级解析：尝试理解复杂的命令行
            debug_echo "尝试高级命令行解析"
            
            # 处理 "bash /path/to/script.sh" 格式
            local bash_script=$(echo "$parent_cmd" | sed -n 's/.*bash[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/p')
            if [ -n "$bash_script" ] && [ -f "$bash_script" ]; then
                debug_echo "方法2成功(bash格式): $bash_script"
                realpath "$bash_script" 2>/dev/null || echo "$bash_script"
                return
            fi
            
            # 处理 "sh /path/to/script.sh" 格式
            local sh_script=$(echo "$parent_cmd" | sed -n 's/.*sh[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/p')
            if [ -n "$sh_script" ] && [ -f "$sh_script" ]; then
                debug_echo "方法2成功(sh格式): $sh_script"
                realpath "$sh_script" 2>/dev/null || echo "$sh_script"
                return
            fi
        fi

        # 如果还是找不到脚本，提供更详细的父进程信息
        local parent_name=$(ps -o comm= -p "$parent_pid" 2>/dev/null)
        local parent_exe=""
        
        # 尝试获取父进程的可执行文件路径
        if [ -r "/proc/$parent_pid/exe" ]; then
            parent_exe=$(readlink "/proc/$parent_pid/exe" 2>/dev/null)
        fi
        
        debug_echo "父进程信息: name=$parent_name, exe=$parent_exe"
        
        if [ -n "$parent_exe" ] && [ "$parent_exe" != "/usr/bin/bash" ] && [ "$parent_exe" != "/bin/bash" ]; then
            echo "$parent_exe"
            return
        elif [ -n "$parent_name" ]; then
            echo "进程: $parent_name (PID: $parent_pid)"
            return
        fi
    fi

    # 方法3: 环境变量方式
    if [ -n "${CALLER_SCRIPT:-}" ]; then
        debug_echo "方法3成功: $CALLER_SCRIPT"
        echo "$CALLER_SCRIPT"
        return
    fi

    # 方法4: 检查当前工作目录和执行方式
    debug_echo "使用fallback方法"
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
        echo "调试选项:"
        echo "  DEBUG_CALLER=1 $0 '消息'  # 显示调用者检测过程"
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