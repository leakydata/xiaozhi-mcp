#!/bin/bash
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取调用者脚本的路径
get_caller_path() {
    parent_pid=$(ps -o ppid= -p $$)
    echo "Debug: parent_pid = '$parent_pid'"
    
    if [ "$(uname)" = "Darwin" ]; then
        # macOS
        parent_cmd=$(ps -o command= -p $parent_pid | awk '{print $2}')
    else
        # Linux
        parent_cmd=$(readlink -f /proc/$parent_pid/exe)
        echo "Debug: parent_cmd = '$parent_cmd'"
        
        # 额外调试信息
        echo "Debug: /proc/$parent_pid/exe exists: $(ls -la /proc/$parent_pid/exe 2>/dev/null || echo 'NO')"
        echo "Debug: parent process info: $(ps -p $parent_pid -o pid,ppid,cmd --no-headers 2>/dev/null || echo 'NO INFO')"
    fi

    if [ -n "$parent_cmd" ]; then
        echo "$parent_cmd"
    else
        echo "直接执行"
    fi
}

echo "=== 调试信息 ==="
echo "当前进程PID: $$"
echo "当前进程信息: $(ps -p $$ -o pid,ppid,cmd --no-headers)"
echo "调用者路径结果: $(get_caller_path)"
echo "================"

msg="$(hostname):\n$(get_caller_path):\n$1"

echo "发送消息: $msg"