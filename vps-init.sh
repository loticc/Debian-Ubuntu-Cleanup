#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# 全局配置
# ============================================================
LOG_FILE="/var/log/vps-init.log"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ============================================================
# 错误处理
# ============================================================
trap 'err=$?; echo "[ERROR] 第 $LINENO 行失败，退出码 $err"; exit $err' ERR

log()  { echo -e "\n[$(date +%H:%M:%S)] $*"; }
warn() { echo -e "\n[WARN] $*"; }

# ============================================================
# 前置检查
# ============================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "请以 root 运行：sudo bash $0"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "检测到系统：$PRETTY_NAME"
        case "$ID" in
            debian|ubuntu) ;;
            *) warn "非 Debian/Ubuntu 系统，脚本可能不兼容。" ;;
        esac
    else
        warn "无法识别系统版本。"
    fi
}

# ============================================================
# 日志设置
# ============================================================
setup_logging() {
    exec > >(tee -a "$LOG_FILE") 2>&1
}

# ============================================================
# 阶段 1：系统精简 + 基础工具（降低内存占用核心）
# ============================================================
phase_cleanup() {
    log "阶段 1/2：系统精简与基础工具安装"

    apt update
    apt install -y --no-install-recommends \
        curl ca-certificates wget gnupg \
        tasksel openssh-server cron \
        iproute2 procps ifupdown net-tools

    systemctl enable --now ssh
    systemctl enable --now cron

    log "移除桌面环境任务..."
    for task in desktop ubuntu-desktop; do
        pkgs=$(tasksel --task-packages "$task" 2>/dev/null || true)
        if [[ -n "$pkgs" ]]; then
            echo "$pkgs" | xargs -r apt purge -y || true
        fi
    done

    log "移除 X 服务器和显示管理器..."
    apt purge -y xserver-xorg-core xserver-xorg gdm3 lightdm sddm 2>/dev/null || true

    apt autoremove --purge -y
    apt clean

    systemctl set-default multi-user.target

    echo ""
    echo "  默认启动目标: $(systemctl get-default)"
    echo "  SSH 状态: $(systemctl is-active ssh)"
    echo "  Cron 状态: $(systemctl is-active cron)"

    if [[ -f /etc/network/interfaces ]] && grep -q "iface" /etc/network/interfaces 2>/dev/null; then
        echo "  网络配置: /etc/network/interfaces (Debian ifupdown)"
    elif [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml &>/dev/null; then
        echo "  网络配置: /etc/netplan (Ubuntu netplan)"
    else
        warn "未检测到标准网络配置，请确认网络可用后再重启！"
    fi

    if ! ip route show default | grep -q default; then
        warn "未检测到默认路由，网络可能异常！"
    fi
}

# ============================================================
# 阶段 2：时区优化
# ============================================================
phase_timezone() {
    log "阶段 2/2：设置时区为 Asia/Shanghai"
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai 2>/dev/null || {
            rm -f /etc/localtime
            ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        }
    else
        rm -f /etc/localtime
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    fi
    echo "  当前时间: $(date)"
}

# ============================================================
# 主流程
# ============================================================
main() {
    check_root
    setup_logging

    echo "=========================================="
    echo "  VPS 精简与优化脚本"
    echo "  支持：Debian 12/13 | Ubuntu 22.04/24.04"
    echo "  目标：移除图形界面，降低内存占用"
    echo "  日志：$LOG_FILE"
    echo "=========================================="

    check_os

    phase_cleanup
    phase_timezone

    echo ""
    echo "=========================================="
    echo "  执行完成 - 最终状态检查"
    echo "=========================================="
    echo "  默认启动目标: $(systemctl get-default)"
    echo "  SSH 状态: $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo 'unknown')"
    echo "  Cron 状态: $(systemctl is-active cron)"
    echo "  当前时间: $(date)"
    echo ""
    echo "  完整日志：$LOG_FILE"
    echo ""
    echo "  下一步（可选）："
    echo "    - 安装 BBR：自行运行对应脚本"
    echo "    - 修改 SSH 端口：自行运行对应脚本"
    echo ""

    read -r -p "是否现在重启？(y/N): " REBOOT_NOW || true
    if [[ "${REBOOT_NOW:-}" =~ ^[Yy]$ ]]; then
        echo "正在重启..."
        sync
        reboot
    else
        echo "跳过重启。"
    fi
}

main "$@"
