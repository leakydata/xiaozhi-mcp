#!/bin/bash

echo "这是调用最终版本的测试脚本"
echo "脚本路径: $0"

# 调用最终版本的钉钉通知脚本
./dingtalk_notify_final.sh "来自最终测试脚本的消息"

echo "测试完成"