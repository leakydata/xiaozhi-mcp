#!/bin/bash

# 钉钉webhook配置
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 自动检测调用者脚本路径（无需修改调用脚本）
get_caller_path() {
    local debug="${DEBUG_CALLER:-0}"
    
    # 调试函数
    debug_log() { [ "$debug" = "1" ] && echo "DEBUG: $*" >&2; }
    
    # 方法1: 深度进程树扫描
    debug_log "开始深度进程树扫描..."
    local pid=$$
    local max_depth=8
    
    for ((depth=0; depth<max_depth; depth++)); do
        # 获取父进程
        local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        debug_log "深度$depth: PID=$pid, PPID=$ppid"
        
        [ -z "$ppid" ] || [ "$ppid" = "1" ] && break
        
        # 获取完整命令行
        local cmd=$(ps -o args= -p "$ppid" 2>/dev/null)
        debug_log "命令: $cmd"
        
        if [ -n "$cmd" ]; then
            # 多种脚本提取模式
            local script_patterns=(
                # bash /path/script.sh
                's/.*bash[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/p'
                # sh /path/script.sh  
                's/.*sh[[:space:]]\+\([^[:space:]]*\.sh\).*/\1/p'
                # /path/script.sh
                's|.*/\([^[:space:]]*\.sh\).*|\1|p'
                # ./script.sh
                's/.*\(\./[^[:space:]]*\.sh\).*/\1/p'
                # script.sh
                's/.*\([^[:space:]/]*\.sh\).*/\1/p'
            )
            
            for pattern in "${script_patterns[@]}"; do
                local candidate=$(echo "$cmd" | sed -n "$pattern")
                debug_log "候选: $candidate"
                
                if [ -n "$candidate" ]; then
                    # 验证文件存在
                    if [ -f "$candidate" ]; then
                        debug_log "找到脚本(直接): $candidate"
                        realpath "$candidate" 2>/dev/null || echo "$candidate"
                        return
                    fi
                    
                    # 相对路径处理
                    if [[ "$candidate" == ./* ]] || [[ "$candidate" != /* ]]; then
                        local full_path="$(pwd)/$candidate"
                        if [ -f "$full_path" ]; then
                            debug_log "找到脚本(相对): $full_path"
                            realpath "$full_path" 2>/dev/null || echo "$full_path"
                            return
                        fi
                    fi
                    
                    # PATH中查找
                    if command -v "$candidate" >/dev/null 2>&1; then
                        local which_result=$(which "$candidate" 2>/dev/null)
                        if [ -f "$which_result" ]; then
                            debug_log "找到脚本(PATH): $which_result"
                            echo "$which_result"
                            return
                        fi
                    fi
                fi
            done
        fi
        
        pid="$ppid"
    done
    
    # 方法2: 环境变量和进程信息分析
    debug_log "分析进程环境信息..."
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    
    if [ -n "$parent_pid" ] && [ -r "/proc/$parent_pid/environ" ]; then
        # 从环境变量中查找脚本信息
        local env_script=$(tr '\0' '\n' < "/proc/$parent_pid/environ" 2>/dev/null | \
                          grep -E '(SCRIPT|BASH_SOURCE|_)=' | \
                          grep -oE '/[^=]*\.(sh|bash|py|pl|rb)\b' | head -1)
        
        if [ -n "$env_script" ] && [ -f "$env_script" ]; then
            debug_log "找到脚本(环境): $env_script"
            realpath "$env_script" 2>/dev/null || echo "$env_script"
            return
        fi
    fi
    
    # 方法3: 当前目录智能推断
    debug_log "智能推断调用者..."
    
    # 查找最近修改的脚本文件
    local recent_scripts=$(find "$(pwd)" -maxdepth 2 -name "*.sh" -type f -readable -mmin -10 2>/dev/null)
    if [ -n "$recent_scripts" ]; then
        # 获取最新的脚本文件
        local newest=$(echo "$recent_scripts" | xargs ls -t 2>/dev/null | head -1)
        if [ -f "$newest" ]; then
            debug_log "找到脚本(推断): $newest"
            realpath "$newest" 2>/dev/null || echo "$newest"
            return
        fi
    fi
    
    # 方法4: 返回详细的进程信息
    debug_log "返回进程信息..."
    local parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    
    if [ -n "$parent_pid" ]; then
        # 获取完整的进程信息
        local proc_info=$(ps -p "$parent_pid" -o pid,ppid,comm,args --no-headers 2>/dev/null)
        if [ -n "$proc_info" ]; then
            echo "进程信息: $proc_info"
        else
            echo "父进程: PID $parent_pid"
        fi
    else
        echo "$(pwd) (无法确定调用者)"
    fi
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