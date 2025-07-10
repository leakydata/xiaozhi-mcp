#!/bin/bash

# 钉钉webhook地址
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 检查参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <命令>"
    echo "示例: $0 'df -h'"
    echo "示例: $0 'free -h'"
    echo "示例: $0 'ps aux | head -10'"
    exit 1
fi

# 获取要执行的命令
command_to_run="$*"

# 获取系统信息
hostname=$(hostname)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
caller_path=$(pwd)

# 执行命令并捕获输出
echo "正在执行命令: $command_to_run"
command_output=$(eval "$command_to_run" 2>&1)
exit_code=$?

# 构建消息内容
if [ $exit_code -eq 0 ]; then
    status_icon="✅"
    status_text="执行成功"
else
    status_icon="❌"
    status_text="执行失败 (退出码: $exit_code)"
fi

message="$status_icon 命令执行报告

🖥️ 主机: $hostname
⏰ 时间: $timestamp
📍 执行位置: $caller_path
📝 命令: $command_to_run
🔧 状态: $status_text

📊 执行结果:
\`\`\`
$command_output
\`\`\`"

# 发送到钉钉
response=$(curl -s "$DINGTALK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"msgtype\": \"text\",
    \"text\": {
      \"content\": \"$message\"
    }
  }")

echo "命令执行结果已发送到钉钉"
echo "钉钉响应: $response"
echo ""
echo "发送的内容："
echo "$message"