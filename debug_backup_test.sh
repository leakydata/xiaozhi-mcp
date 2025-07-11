#!/bin/bash

echo "这是调试版本的备份脚本: $0"

# 使用调试模式调用钉钉通知脚本
DEBUG_CALLER=1 ./dingtalk_improved_caller.sh "错误：数据库备份失败（调试模式）"

echo "调试测试完成"