# 钉钉Webhook脚本集合

## 概述
为了满足通过钉钉webhook发送`df -h`等系统命令结果的需求，我创建了三个不同功能的脚本。

## 脚本列表

### 1. dingtalk_notify.sh - 基础通知脚本
**功能**: 发送基本系统信息和磁盘使用情况
**特点**: 
- 显示主机名、路径信息
- 自动包含`df -h`结果
- 使用emoji美化显示

**使用方法**:
```bash
./dingtalk_notify.sh
```

**输出示例**:
```
🖥️ 主机: cursor
📍 调用者路径: /workspace
📄 脚本路径: /workspace/dingtalk_notify.sh
📂 当前目录: /workspace

💾 磁盘使用情况:
Filesystem      Size  Used Avail Use% Mounted on
overlay         512G   17G  496G   4% /
tmpfs            64M     0   64M   0% /dev
...
```

### 2. dingtalk_disk_monitor.sh - 磁盘监控脚本
**功能**: 专门的磁盘空间监控和告警
**特点**:
- 自动检测磁盘使用率超过80%的分区
- 显示最高使用率
- 有警告和正常两种不同的消息格式
- 包含时间戳

**使用方法**:
```bash
./dingtalk_disk_monitor.sh
```

**正常状态输出**:
```
✅ 磁盘监控报告

🖥️ 主机: cursor
⏰ 时间: 2025-07-10 09:37:49
🟢 最高使用率: 4%
✅ 所有分区使用率正常
```

**警告状态输出**:
```
⚠️ 磁盘空间警告 ⚠️

🖥️ 主机: cursor
⏰ 时间: 2025-07-10 09:37:49
🔴 最高使用率: 85%

⚠️ 超过80%的分区:
/dev/sda1 85%
```

### 3. dingtalk_send_command.sh - 通用命令执行脚本
**功能**: 执行任意命令并发送结果到钉钉
**特点**:
- 支持任意shell命令
- 显示命令执行状态（成功/失败）
- 捕获错误输出
- 显示退出码

**使用方法**:
```bash
./dingtalk_send_command.sh "命令"
```

**示例用法**:
```bash
# 发送磁盘使用情况
./dingtalk_send_command.sh "df -h"

# 发送内存使用情况
./dingtalk_send_command.sh "free -h"

# 发送进程信息
./dingtalk_send_command.sh "ps aux | head -10"

# 发送网络连接状态
./dingtalk_send_command.sh "netstat -tuln"

# 发送系统负载
./dingtalk_send_command.sh "uptime"
```

**输出示例**:
```
✅ 命令执行报告

🖥️ 主机: cursor
⏰ 时间: 2025-07-10 09:38:36
📍 执行位置: /workspace
📝 命令: df -h
🔧 状态: 执行成功

📊 执行结果:
```
Filesystem      Size  Used Avail Use% Mounted on
overlay         512G   17G  496G   4% /
...
```
```

## 使用建议

### 场景选择
- **日常监控**: 使用 `dingtalk_disk_monitor.sh`
- **一次性查询**: 使用 `dingtalk_send_command.sh`
- **基础信息**: 使用 `dingtalk_notify.sh`

### 定时任务配置
可以将脚本添加到crontab中实现定时监控：

```bash
# 每小时检查磁盘使用情况
0 * * * * /workspace/dingtalk_disk_monitor.sh

# 每天早上8点发送系统状态
0 8 * * * /workspace/dingtalk_send_command.sh "df -h && free -h && uptime"
```

### 安全提醒
- webhook URL包含access_token，请妥善保管
- 避免执行可能泄露敏感信息的命令
- 建议在生产环境中使用更安全的认证方式

## 测试状态
✅ 所有脚本已测试通过
✅ 钉钉API响应正常 (`{"errcode":0,"errmsg":"ok"}`)
✅ 消息格式正确显示