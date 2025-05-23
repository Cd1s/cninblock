#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要root权限运行"
    exit 1
fi

# 确保必要的工具已安装
check_requirements() {
    command -v ipset >/dev/null 2>&1 || { echo "请先安装 ipset"; exit 1; }
    command -v iptables >/dev/null 2>&1 || { echo "请先安装 iptables"; exit 1; }
    command -v curl >/dev/null 2>&1 || { echo "请先安装 curl"; exit 1; }
}

# 初始化 ipset
init_ipset() {
    # 删除已存在的 ipset
    ipset destroy china_ip 2>/dev/null
    
    # 创建新的 ipset
    ipset create china_ip hash:net
    
    # 下载并添加中国 IP 段
    echo "正在下载中国IP列表..."
    curl -s https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt | while read line; do
        ipset add china_ip $line 2>/dev/null
    done
}

# 配置 iptables 规则
setup_iptables() {
    local port="$1"
    
    # 清除已有规则和自定义链
    iptables -F
    iptables -X
    
    # 设置默认策略
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # 允许本地回环接口
    iptables -A INPUT -i lo -j ACCEPT
    
    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # 如果指定了端口，添加端口规则
    if [ ! -z "$port" ]; then
        # 拒绝来自中国IP的指定端口访问
        iptables -A INPUT -p tcp -m set --match-set china_ip src --dport $port -j DROP
        # 允许其他IP访问指定端口
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
    else
        # 拒绝来自中国IP的所有访问
        iptables -A INPUT -m set --match-set china_ip src -j DROP
        # 允许其他所有IP的访问
        iptables -A INPUT -j ACCEPT
    fi
}

# 卸载所有规则
uninstall_all() {
    echo "正在卸载防火墙规则..."
    
    # 清除 iptables 规则
    iptables -F
    iptables -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # 清除 ipset
    ipset destroy china_ip 2>/dev/null
    
    echo "防火墙规则已完全清除"
}

# 主函数
main() {
    case "$1" in
        "install")
            check_requirements
            init_ipset
            if [ ! -z "$2" ]; then
                setup_iptables "$2"
                echo "已设置防火墙规则，只允许非中国IP访问端口 $2"
            else
                setup_iptables
                echo "已设置防火墙规则，只允许非中国IP访问所有端口"
            fi
            ;;
        "uninstall")
            uninstall_all
            ;;
        *)
            echo "用法: $0 {install|uninstall} [port]"
            echo "示例:"
            echo "  $0 install      # 安装防火墙规则，只允许海外IP访问"
            echo "  $0 install 80   # 安装防火墙规则，只允许海外IP访问80端口"
            echo "  $0 uninstall    # 卸载所有防火墙规则"
            exit 1
            ;;
    esac
}

main "$@" 
