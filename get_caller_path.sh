# 获取调用者脚本的路径
get_caller_path() {
    parent_pid=$(ps -o ppid= -p $$)
    if [ "$(uname)" = "Darwin" ]; then
        # macOS
        parent_cmd=$(ps -o command= -p $parent_pid | awk '{print $2}')
        # 确保返回绝对路径
        if [ -n "$parent_cmd" ]; then
            # 如果路径不是以/开头，则转换为绝对路径
            if [ "${parent_cmd#/}" = "$parent_cmd" ]; then
                # 相对路径，需要转换为绝对路径
                if command -v realpath >/dev/null 2>&1; then
                    parent_cmd=$(realpath "$parent_cmd")
                elif command -v greadlink >/dev/null 2>&1; then
                    parent_cmd=$(greadlink -f "$parent_cmd")
                else
                    # 使用cd和pwd的方法
                    if [ -f "$parent_cmd" ]; then
                        parent_dir=$(dirname "$parent_cmd")
                        parent_file=$(basename "$parent_cmd")
                        parent_cmd=$(cd "$parent_dir" && pwd)/"$parent_file"
                    elif [ -d "$parent_cmd" ]; then
                        parent_cmd=$(cd "$parent_cmd" && pwd)
                    fi
                fi
            fi
        fi
    else
        # Linux
        parent_cmd=$(readlink -f /proc/$parent_pid/exe)
    fi

    if [ -n "$parent_cmd" ]; then
        echo "$parent_cmd"
    else
        echo "直接执行"
    fi
}