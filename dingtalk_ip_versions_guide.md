# 钉钉Webhook IP版本使用指南

## 📋 版本对比

现在有三个主要版本的钉钉通知脚本：

| 版本 | 文件名 | 功能特点 | 适用场景 |
|------|--------|----------|----------|
| **基础版** | `dingtalk_notify_final.sh` | 基础功能，调用者路径检测 | 简单通知 |
| **完整版** | `dingtalk_notify_with_ip.sh` | 包含公网IP和内网IP | 详细监控 |
| **快速版** | `dingtalk_notify_quick.sh` | 可配置的IP获取选项 | 灵活使用 |

## 🚀 基础版本 (`dingtalk_notify_final.sh`)

### 功能：
- ✅ 主机名
- ✅ 时间戳  
- ✅ 调用者路径检测
- ✅ 自定义消息

### 使用：
```bash
./dingtalk_notify_final.sh "服务器状态正常"
```

### 输出示例：
```
📊 系统通知

🖥️ 主机: cursor
⏰ 时间: 2025-07-11 02:05:07
📍 调用者: /workspace/test_script.sh
💬 消息: 服务器状态正常
```

## 🌐 完整版本 (`dingtalk_notify_with_ip.sh`)

### 功能：
- ✅ 基础版所有功能
- ✅ **公网IP地址**
- ✅ **内网IP地址**
- ✅ 多服务IP检测（提高成功率）

### 使用：
```bash
./dingtalk_notify_with_ip.sh "带IP信息的通知"
```

### 输出示例：
```
📊 系统通知

🖥️ 主机: cursor
⏰ 时间: 2025-07-11 02:11:53
📍 调用者: /workspace/test_script.sh
🌐 公网IP: 107.21.235.172
🏠 内网IP: 172.17.0.2
💬 消息: 带IP信息的通知
```

### IP获取服务：
- `ipinfo.io/ip`
- `ifconfig.me`
- `checkip.amazonaws.com`
- `ipecho.net/plain`
- `icanhazip.com`

## ⚡ 快速版本 (`dingtalk_notify_quick.sh`)

### 功能：
- ✅ 完整版所有功能
- ✅ **环境变量控制**
- ✅ **简化模式**
- ✅ **快速模式**（跳过IP获取）

### 环境变量选项：

| 变量 | 作用 | 示例 |
|------|------|------|
| `SKIP_PUBLIC_IP=1` | 跳过公网IP获取（加快速度） | `SKIP_PUBLIC_IP=1 ./script.sh "快速通知"` |
| `SKIP_PRIVATE_IP=1` | 跳过内网IP获取 | `SKIP_PRIVATE_IP=1 ./script.sh "消息"` |
| `SIMPLE_MODE=1` | 简化输出格式 | `SIMPLE_MODE=1 ./script.sh "简单通知"` |

### 使用示例：

#### 1. 完整模式（默认）：
```bash
./dingtalk_notify_quick.sh "完整信息通知"
```
输出包含所有信息和IP地址。

#### 2. 快速模式（跳过公网IP）：
```bash
SKIP_PUBLIC_IP=1 ./dingtalk_notify_quick.sh "快速通知"
```
只获取内网IP，节省时间。

#### 3. 超快模式（跳过所有IP）：
```bash
SKIP_PUBLIC_IP=1 SKIP_PRIVATE_IP=1 ./dingtalk_notify_quick.sh "超快通知"
```
不获取任何IP信息，最快发送。

#### 4. 简化模式：
```bash
SIMPLE_MODE=1 ./dingtalk_notify_quick.sh "简洁通知"
```
消息格式：
```
📱 cursor | test_script.sh
⏰ 2025-07-11 02:13:41
💬 简洁通知
```

## 🎯 使用建议

### 场景选择：

| 场景 | 推荐版本 | 理由 |
|------|----------|------|
| **简单日志** | 基础版 | 轻量级，速度快 |
| **服务器监控** | 完整版 | 网络信息完整 |
| **频繁通知** | 快速版 + `SKIP_PUBLIC_IP=1` | 避免网络延迟 |
| **批量脚本** | 快速版 + `SIMPLE_MODE=1` | 输出简洁 |
| **紧急告警** | 快速版 + 跳过所有IP | 最快发送 |

### 性能对比：

| 模式 | 执行时间 | 网络请求 | 信息完整度 |
|------|----------|----------|------------|
| 基础版 | ~0.1s | 仅钉钉API | ⭐⭐⭐ |
| 完整版 | ~1-3s | 钉钉API + IP查询 | ⭐⭐⭐⭐⭐ |
| 快速版（跳过公网IP） | ~0.2s | 钉钉API | ⭐⭐⭐⭐ |
| 快速版（简化模式） | ~0.1s | 仅钉钉API | ⭐⭐⭐ |

## 📊 实际测试结果

### 公网IP获取测试：
```bash
# 第一次运行
$ ./dingtalk_notify_with_ip.sh "测试1"
公网IP: 107.21.235.172

# 第二次运行  
$ ./test_ip_caller.sh
公网IP: 34.224.177.102  # IP可能会变化（负载均衡）
```

### 内网IP获取：
```bash
内网IP: 172.17.0.2  # Docker容器网络
```

## 🔧 自定义配置

### 1. 修改webhook地址：
```bash
# 在脚本开头修改
DINGTALK_WEBHOOK="你的webhook地址"
```

### 2. 创建快捷脚本：
```bash
#!/bin/bash
# my_notify.sh
export SKIP_PUBLIC_IP=1
export SIMPLE_MODE=1
./dingtalk_notify_quick.sh "$@"
```

### 3. 添加到PATH：
```bash
sudo cp dingtalk_notify_quick.sh /usr/local/bin/dingmsg
sudo chmod +x /usr/local/bin/dingmsg

# 然后可以全局使用
dingmsg "任务完成"
SIMPLE_MODE=1 dingmsg "简单通知"
```

## 🎉 总结

现在你有了三个功能逐步增强的钉钉通知脚本：

1. **`dingtalk_notify_final.sh`** - 修复了调用者路径问题的基础版本
2. **`dingtalk_notify_with_ip.sh`** - 添加了公网IP和内网IP的完整版本
3. **`dingtalk_notify_quick.sh`** - 可配置的快速版本，适合各种场景

选择最适合你需求的版本使用即可！🚀