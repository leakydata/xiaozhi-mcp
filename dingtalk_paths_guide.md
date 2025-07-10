# 钉钉Webhook调用者路径获取指南

## 概述
在bash脚本中，有多种方式获取"调用者路径"，根据不同的需求选择合适的方法。

## 路径获取方式

### 1. 当前工作目录 (Current Working Directory)
```bash
current_dir=$(pwd)
# 或者
current_dir="$PWD"
```
- **说明**: 获取脚本运行时的当前工作目录
- **用途**: 适用于需要知道脚本从哪个目录被调用的场景

### 2. 脚本所在目录 (Script Directory)
```bash
script_dir=$(dirname "$(realpath "$0")")
```
- **说明**: 获取脚本文件实际存放的目录
- **用途**: 适用于需要相对于脚本位置操作文件的场景

### 3. 脚本完整路径 (Full Script Path)
```bash
script_path=$(realpath "$0")
```
- **说明**: 获取脚本的完整绝对路径
- **用途**: 适用于需要完整路径信息的日志记录

### 4. 脚本名称 (Script Name)
```bash
script_name=$(basename "$0")
```
- **说明**: 仅获取脚本文件名（不包含路径）
- **用途**: 适用于日志标识或简单显示

## 使用场景示例

### 场景1: 监控脚本执行位置
```bash
调用者路径=$(pwd)
message="脚本在目录 $调用者路径 中被执行"
```

### 场景2: 相对于脚本位置的操作
```bash
调用者路径=$(dirname "$(realpath "$0")")
message="脚本位于 $调用者路径 目录"
```

### 场景3: 完整的执行信息
```bash
调用者路径="$(pwd) -> $(realpath "$0")"
message="从 $(pwd) 执行了 $(realpath "$0")"
```

## 修正后的钉钉webhook代码

原始代码存在的问题：
1. JSON格式错误（引号使用不当）
2. 变量引用语法错误
3. curl命令参数错误

修正后的代码请参考 `dingtalk_notify.sh` 文件。

## 测试方法

运行脚本：
```bash
./dingtalk_notify.sh
```

从不同目录运行：
```bash
cd /tmp
/workspace/dingtalk_notify.sh
```

观察路径信息的差异。