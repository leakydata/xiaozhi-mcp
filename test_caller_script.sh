#!/bin/bash

echo "这是测试调用脚本：$0"
echo "正在调用钉钉通知脚本..."

# 调用钉钉通知脚本
./dingtalk_fixed.sh "来自测试脚本的消息"

echo "调用完成"