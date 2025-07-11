#!/bin/bash

echo "这是自动检测测试脚本: $0"

# 直接调用钉钉通知脚本，不修改任何代码
./dingtalk_auto_caller.sh "错误：数据库 m2898_string2 备份失败，请检查数据库连接和权限！"

echo "测试完成"