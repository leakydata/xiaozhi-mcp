#!/bin/bash

echo "这是测试带IP功能的脚本"
echo "脚本路径: $0"
echo "正在调用钉钉通知脚本（带IP信息）..."

# 调用带IP功能的钉钉通知脚本
./dingtalk_notify_with_ip.sh "来自测试脚本的消息 - 包含IP信息"

echo "测试完成"