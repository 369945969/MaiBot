#!/bin/bash
# MaiBot 启动脚本
# 如果已有实例在运行，先终止再重新启动

set -euo pipefail

# 工作目录为脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# PID 文件路径
PID_FILE="$SCRIPT_DIR/.maibot.pid"

# 颜色定义
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
RESET='\e[0m'

log_info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*"; }

# 检查进程是否存活
is_process_alive() {
    local pid="$1"
    # 过滤掉 PID 1（系统进程）和自身
    if [[ "$pid" -le 1 ]]; then
        return 1
    fi
    ps -p "$pid" -o pid= >/dev/null 2>&1
}

# 终止已有实例
stop_existing() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE")"

        if is_process_alive "$old_pid"; then
            log_warn "发现正在运行的 MaiBot 进程 (PID: $old_pid)，正在终止..."

            # 发送 SIGTERM，等待进程优雅退出
            kill -TERM "$old_pid" 2>/dev/null || true

            # 等待最多 15 秒
            local wait_count=0
            while is_process_alive "$old_pid" && [[ $wait_count -lt 15 ]]; do
                sleep 1
                wait_count=$((wait_count + 1))
            done

            if is_process_alive "$old_pid"; then
                log_warn "进程未在 15 秒内退出，强制终止..."
                kill -9 "$old_pid" 2>/dev/null || true
                sleep 1
            fi

            if is_process_alive "$old_pid"; then
                log_error "无法终止进程 $old_pid，请手动检查"
                exit 1
            fi

            log_info "已终止旧进程 (PID: $old_pid)"
        else
            log_warn "PID 文件存在但进程 $old_pid 已不在运行，清理残留 PID 文件"
        fi

        rm -f "$PID_FILE"
    fi

    # 兼容检查：即使没有 PID 文件，也扫描是否有 bot.py 进程在跑
    local running_pids
    running_pids="$(pgrep -f "python.*bot.py" 2>/dev/null || true)"
    if [[ -n "$running_pids" ]]; then
        # 排除当前脚本自身可能触发的 pgrep 匹配
        for pid in $running_pids; do
            if is_process_alive "$pid"; then
                log_warn "发现残留 MaiBot 进程 (PID: $pid)，正在终止..."
                kill -TERM "$pid" 2>/dev/null || true
                sleep 2
                if is_process_alive "$pid"; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
    fi
}

# 启动 MaiBot
start_maibot() {
    log_info "正在启动 MaiBot..."

    # 使用 uv run 启动，确保虚拟环境正确
    # Runner 进程会被 bot.py 的 run_runner_process 管理
    # 这里只启动 Runner，Worker 由 Runner 管理
    nohup uv run python bot.py >> "$SCRIPT_DIR/logs/maibot.log" 2>&1 &
    local pid=$!

    # 写入 PID 文件（记录 Runner 进程）
    echo "$pid" > "$PID_FILE"

    # 等待短暂时间确认进程存活
    sleep 2
    if is_process_alive "$pid"; then
        log_info "MaiBot 已启动 (Runner PID: $pid)"
        log_info "日志文件: $SCRIPT_DIR/logs/maibot.log"
    else
        log_error "MaiBot 启动失败，请检查日志: $SCRIPT_DIR/logs/maibot.log"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# 创建日志目录
mkdir -p "$SCRIPT_DIR/logs"

# 主流程：先停后启
stop_existing
start_maibot