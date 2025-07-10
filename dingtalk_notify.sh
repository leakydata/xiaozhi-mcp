#!/bin/bash

# 钉钉webhook地址
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=d9593f38aecf80af94e4e77ee3c82fbec0e2fa9326612bc9d9a3b2041c837c7e"

# 获取各种路径信息
# 1. 当前工作目录
current_dir=$(pwd)

# 2. 脚本所在目录
script_dir=$(dirname "$(realpath "$0")")

# 3. 脚本的完整路径
script_path=$(realpath "$0")

# 4. 脚本名称
script_name=$(basename "$0")

# 5. 主机名
hostname=$(hostname)

# 你可以根据需要选择使用哪个路径
# 这里演示几种常见的用法：

# 使用当前工作目录作为调用者路径
caller_path="$current_dir"

# 或者使用脚本所在目录
# caller_path="$script_dir"

# 或者使用完整的脚本路径
# caller_path="$script_path"

# 构建消息内容
message="主机: $hostname
调用者路径: $caller_path
脚本路径: $script_path
当前目录: $current_dir"

# 发送到钉钉
curl -s "$DINGTALK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"msgtype\": \"text\",
    \"text\": {
      \"content\": \"$message\"
    }
  }"

echo "消息已发送到钉钉"
echo "发送的内容："
echo "$message"