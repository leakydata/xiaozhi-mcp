#!/bin/bash

# 钉钉webhook地址
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取系统信息
hostname=$(hostname)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# 获取磁盘使用情况
disk_usage=$(df -h)

# 获取磁盘使用率最高的分区
max_usage=$(df -h | awk 'NR>1 {gsub(/%/, "", $5); if($5 > max) max=$5} END {print max "%"}')

# 检查是否有磁盘使用率超过80%的分区
warning_disks=$(df -h | awk 'NR>1 {gsub(/%/, "", $5); if($5 > 80) print $1 " " $5 "%"}')

# 构建消息内容
if [ -n "$warning_disks" ]; then
    message="⚠️ 磁盘空间警告 ⚠️

🖥️ 主机: $hostname
⏰ 时间: $timestamp
🔴 最高使用率: $max_usage

⚠️ 超过80%的分区:
$warning_disks

📊 完整磁盘使用情况:
\`\`\`
$disk_usage
\`\`\`"
else
    message="✅ 磁盘监控报告

🖥️ 主机: $hostname
⏰ 时间: $timestamp
🟢 最高使用率: $max_usage
✅ 所有分区使用率正常

📊 磁盘使用情况:
\`\`\`
$disk_usage
\`\`\`"
fi

# 发送到钉钉
response=$(curl -s "$DINGTALK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"msgtype\": \"text\",
    \"text\": {
      \"content\": \"$message\"
    }
  }")

echo "磁盘监控消息已发送到钉钉"
echo "钉钉响应: $response"
echo ""
echo "发送的内容："
echo "$message"