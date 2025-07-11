#!/bin/bash

# 数据库备份脚本示例
# 这个脚本演示如何确保钉钉通知能正确显示调用者路径

# 设置脚本路径环境变量（推荐方法）
export CALLER_SCRIPT="$(realpath "$0")"

# 备份配置
DB_NAME="m2898_string2"
BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "开始备份数据库: $DB_NAME"
echo "备份脚本: $CALLER_SCRIPT"

# 模拟备份过程
simulate_backup() {
    echo "正在备份数据库 $DB_NAME ..."
    
    # 这里放你的实际备份命令，例如：
    # mysqldump -u user -p password $DB_NAME > $BACKUP_DIR/${DB_NAME}_${DATE}.sql
    
    # 模拟备份失败（用于测试）
    return 1  # 0=成功, 1=失败
}

# 执行备份
if simulate_backup; then
    echo "✅ 备份成功"
    ./dingtalk_notify_production.sh "✅ 数据库 $DB_NAME 备份成功！备份时间：$(date)"
else
    echo "❌ 备份失败"
    ./dingtalk_notify_production.sh "❌ 错误：数据库 $DB_NAME 备份失败，请检查数据库连接和权限！"
fi

echo "备份脚本执行完成"