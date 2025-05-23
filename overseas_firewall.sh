#!/bin/bash

# OverseasOnlyBlocker 2.0
# 🌏 仅允许海外 IP 入站连接｜❌ 拒绝中国 IP 入站｜🌐 支持 IPv4 + IPv6｜🎯 支持端口范围放行

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # 恢复默认颜色

# 变量定义
CONFIG_DIR="/etc/overseas_only_blocker"
IPV4_IPSET_NAME="block_cn_ipv4"
IPV6_IPSET_NAME="block_cn_ipv6"
SERVICE_FILE="/etc/systemd/system/overseas_only_blocker.service"
STARTUP_SCRIPT="$CONFIG_DIR/startup_script.sh"
ALLOWED_PORTS_FILE="$CONFIG_DIR/allowed_ports.txt"

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        exit 1
    fi
}

# 检查系统环境
check_environment() {
    echo -e "${BLUE}🔍 检查系统环境...${NC}"
    
    # 创建配置目录
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    # 检查依赖工具
    local missing_deps=()
    for cmd in wget iptables ip6tables ipset; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}缺少依赖: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}正在安装依赖...${NC}"
        
        if command -v apt &> /dev/null; then
            apt update && apt install -y wget iptables ipset
        elif command -v yum &> /dev/null; then
            yum install -y wget iptables ipset
        elif command -v dnf &> /dev/null; then
            dnf install -y wget iptables ipset
        else
            echo -e "${RED}无法自动安装依赖，请手动安装: ${missing_deps[*]}${NC}"
            exit 1
        fi
    fi
    
    # 初始化允许的端口文件
    if [ ! -f "$ALLOWED_PORTS_FILE" ]; then
        echo "22" > "$ALLOWED_PORTS_FILE"  # 默认允许SSH
    fi
    
    echo -e "${GREEN}✅ 系统环境检查完成${NC}"
}

# 下载中国IP列表 (IPv4)
download_cn_ipv4_list() {
    echo -e "${BLUE}📥 正在下载中国IPv4列表...${NC}"
    wget -q -O /tmp/cn_ipv4.zone https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
    if [ $? -ne 0 ] || [ ! -s /tmp/cn_ipv4.zone ]; then
        echo -e "${YELLOW}主源失败，尝试备用 APNIC 来源...${NC}"
        wget -q -O- 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | \
        awk -F\| '/CN\|ipv4/ {print $4"/"32-log($5)/log(2)}' > /tmp/cn_ipv4.zone
    fi
    if [ ! -s /tmp/cn_ipv4.zone ]; then
        echo -e "${RED}无法获取中国IPv4列表，请检查网络连接${NC}"
        return 1
    fi
    echo -e "${GREEN}成功下载中国IPv4列表${NC}"
    return 0
}

# 下载中国IP列表 (IPv6)
download_cn_ipv6_list() {
    echo -e "${BLUE}📥 正在下载中国IPv6列表...${NC}"
    wget -q -O /tmp/cn_ipv6.zone https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ipv6_list.txt
    if [ $? -ne 0 ] || [ ! -s /tmp/cn_ipv6.zone ]; then
        echo -e "${YELLOW}主源失败，尝试备用 APNIC 来源...${NC}"
        wget -q -O- 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | \
        awk -F\| '/CN\|ipv6/ {print $4"/"$5}' > /tmp/cn_ipv6.zone
    fi
    if [ ! -s /tmp/cn_ipv6.zone ]; then
        echo -e "${RED}无法获取中国IPv6列表，请检查网络连接${NC}"
        return 1
    fi
    echo -e "${GREEN}成功下载中国IPv6列表${NC}"
    return 0
}

# 创建开机启动脚本
create_startup_script() {
    echo -e "${BLUE}📝 创建开机启动脚本...${NC}"
    
    cat > "$STARTUP_SCRIPT" << EOL
#!/bin/bash

# OverseasOnlyBlocker 开机启动脚本
echo "正在启动 OverseasOnlyBlocker 防火墙规则..." > /var/log/overseas_only_blocker.log

# 确保目录和端口文件存在
if [ ! -f /etc/overseas_only_blocker/allowed_ports.txt ]; then
    echo "22" > /etc/overseas_only_blocker/allowed_ports.txt
fi

# IPv4 配置
if [ -f /etc/overseas_only_blocker/ipv4_enabled ]; then
    # 创建 ipset
    ipset create $IPV4_IPSET_NAME hash:net family inet hashsize 1024 maxelem 65536 -exist
    
    # 加载中国 IP 列表
    if [ -f /etc/overseas_only_blocker/cn_ipv4.zone ]; then
        while read ip; do
            ipset add $IPV4_IPSET_NAME \$ip -exist
        done < /etc/overseas_only_blocker/cn_ipv4.zone
    fi
    
    # 配置 iptables 规则
    iptables -F INPUT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    
    # 对放行列表中的端口进行中国IP封禁
    while read port; do
        if [[ \$port == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "\$port"
            iptables -A INPUT -p tcp --match multiport --dports \$start_port:\$end_port -m set --match-set $IPV4_IPSET_NAME src -j DROP
            iptables -A INPUT -p udp --match multiport --dports \$start_port:\$end_port -m set --match-set $IPV4_IPSET_NAME src -j DROP
        else
            iptables -A INPUT -p tcp --dport \$port -m set --match-set $IPV4_IPSET_NAME src -j DROP
            iptables -A INPUT -p udp --dport \$port -m set --match-set $IPV4_IPSET_NAME src -j DROP
        fi
    done < /etc/overseas_only_blocker/allowed_ports.txt
    
    # 允许所有其他流量
    iptables -A INPUT -j ACCEPT
fi

# IPv6 配置
if [ -f /etc/overseas_only_blocker/ipv6_enabled ]; then
    # 创建 ipset
    ipset create $IPV6_IPSET_NAME hash:net family inet6 hashsize 1024 maxelem 65536 -exist
    
    # 加载中国 IP 列表
    if [ -f /etc/overseas_only_blocker/cn_ipv6.zone ]; then
        while read ip; do
            ipset add $IPV6_IPSET_NAME \$ip -exist
        done < /etc/overseas_only_blocker/cn_ipv6.zone
    fi
    
    # 配置 ip6tables 规则
    ip6tables -F INPUT
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT
    
    # 对放行列表中的端口进行中国IP封禁
    while read port; do
        if [[ \$port == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "\$port"
            ip6tables -A INPUT -p tcp --match multiport --dports \$start_port:\$end_port -m set --match-set $IPV6_IPSET_NAME src -j DROP
            ip6tables -A INPUT -p udp --match multiport --dports \$start_port:\$end_port -m set --match-set $IPV6_IPSET_NAME src -j DROP
        else
            ip6tables -A INPUT -p tcp --dport \$port -m set --match-set $IPV6_IPSET_NAME src -j DROP
            ip6tables -A INPUT -p udp --dport \$port -m set --match-set $IPV6_IPSET_NAME src -j DROP
        fi
    done < /etc/overseas_only_blocker/allowed_ports.txt
    
    # 允许所有其他流量
    ip6tables -A INPUT -j ACCEPT
fi

exit 0
EOL
    
    chmod +x "$STARTUP_SCRIPT"
    
    # 创建systemd服务
    cat > "$SERVICE_FILE" << EOL
[Unit]
Description=OverseasOnlyBlocker Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$STARTUP_SCRIPT
RemainAfterExit=true
TimeoutSec=180

[Install]
WantedBy=multi-user.target
EOL
    
    systemctl daemon-reload
    systemctl enable overseas_only_blocker.service
    
    echo -e "${GREEN}✅ 开机启动配置完成${NC}"
}

# 安装 IPv4 海外入站
install_ipv4_overseas() {
    echo -e "${BLUE}🛠️ 安装 IPv4 海外入站...${NC}"
    
    # 下载 IPv4 列表
    download_cn_ipv4_list
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 创建 ipset
    ipset create $IPV4_IPSET_NAME hash:net family inet hashsize 1024 maxelem 65536 -exist
    
    # 加载中国 IP 列表
    while read ip; do
        ipset add $IPV4_IPSET_NAME $ip -exist
    done < /tmp/cn_ipv4.zone
    
    # 保存 IP 列表到配置目录
    cp /tmp/cn_ipv4.zone "$CONFIG_DIR/cn_ipv4.zone"
    
    # 配置 iptables 规则
    iptables -F INPUT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    
    # 对放行列表中的端口进行中国IP封禁
    while read port; do
        if [[ $port == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port"
            # 先允许非中国IP访问这些端口
            iptables -A INPUT -p tcp --match multiport --dports $start_port:$end_port -m set --match-set $IPV4_IPSET_NAME src -j DROP
            iptables -A INPUT -p udp --match multiport --dports $start_port:$end_port -m set --match-set $IPV4_IPSET_NAME src -j DROP
        else
            # 先允许非中国IP访问这个端口
            iptables -A INPUT -p tcp --dport $port -m set --match-set $IPV4_IPSET_NAME src -j DROP
            iptables -A INPUT -p udp --dport $port -m set --match-set $IPV4_IPSET_NAME src -j DROP
        fi
    done < "$ALLOWED_PORTS_FILE"
    
    # 允许所有其他流量
    iptables -A INPUT -j ACCEPT
    
    # 标记 IPv4 功能已启用
    touch "$CONFIG_DIR/ipv4_enabled"
    
    echo -e "${GREEN}✅ IPv4 海外入站已安装${NC}"
    return 0
}

# 安装 IPv6 海外入站
install_ipv6_overseas() {
    echo -e "${BLUE}🛠️ 安装 IPv6 海外入站...${NC}"
    
    # 下载 IPv6 列表
    download_cn_ipv6_list
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 创建 ipset
    ipset create $IPV6_IPSET_NAME hash:net family inet6 hashsize 1024 maxelem 65536 -exist
    
    # 加载中国 IP 列表
    while read ip; do
        ipset add $IPV6_IPSET_NAME $ip -exist
    done < /tmp/cn_ipv6.zone
    
    # 保存 IP 列表到配置目录
    cp /tmp/cn_ipv6.zone "$CONFIG_DIR/cn_ipv6.zone"
    
    # 配置 ip6tables 规则
    ip6tables -F INPUT
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT
    
    # 对放行列表中的端口进行中国IP封禁
    while read port; do
        if [[ $port == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port"
            # 先允许非中国IP访问这些端口
            ip6tables -A INPUT -p tcp --match multiport --dports $start_port:$end_port -m set --match-set $IPV6_IPSET_NAME src -j DROP
            ip6tables -A INPUT -p udp --match multiport --dports $start_port:$end_port -m set --match-set $IPV6_IPSET_NAME src -j DROP
        else
            # 先允许非中国IP访问这个端口
            ip6tables -A INPUT -p tcp --dport $port -m set --match-set $IPV6_IPSET_NAME src -j DROP
            ip6tables -A INPUT -p udp --dport $port -m set --match-set $IPV6_IPSET_NAME src -j DROP
        fi
    done < "$ALLOWED_PORTS_FILE"
    
    # 允许所有其他流量
    ip6tables -A INPUT -j ACCEPT
    
    # 标记 IPv6 功能已启用
    touch "$CONFIG_DIR/ipv6_enabled"
    
    echo -e "${GREEN}✅ IPv6 海外入站已安装${NC}"
    return 0
}

# 查看放行端口
view_allowed_ports() {
    echo -e "${BLUE}📋 当前放行端口列表:${NC}"
    if [ -f "$ALLOWED_PORTS_FILE" ]; then
        cat "$ALLOWED_PORTS_FILE" | while read port; do
            if [[ $port == *-* ]]; then
                echo -e "${GREEN}端口范围: $port${NC}"
            else
                echo -e "${GREEN}端口: $port${NC}"
            fi
        done
    else
        echo -e "${YELLOW}尚未配置放行端口${NC}"
    fi
}

# 添加放行端口
add_allowed_port() {
    echo -e "${BLUE}➕ 添加放行端口${NC}"
    
    echo -e "请输入要放行的端口(支持单个端口如 80 或端口范围如 8000-9000):"
    read port_input
    
    # 验证端口输入格式
    if [[ $port_input =~ ^[0-9]+$ ]]; then
        if [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
            echo -e "${RED}错误: 端口范围必须在 1-65535 之间${NC}"
            return 1
        fi
    elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
        start_port=$(echo $port_input | cut -d'-' -f1)
        end_port=$(echo $port_input | cut -d'-' -f2)
        
        if [ "$start_port" -lt 1 ] || [ "$start_port" -gt 65535 ] || [ "$end_port" -lt 1 ] || [ "$end_port" -gt 65535 ]; then
            echo -e "${RED}错误: 端口范围必须在 1-65535 之间${NC}"
            return 1
        fi
        
        if [ "$start_port" -ge "$end_port" ]; then
            echo -e "${RED}错误: 起始端口必须小于结束端口${NC}"
            return 1
        fi
    else
        echo -e "${RED}错误: 无效的端口格式${NC}"
        return 1
    fi
    
    # 检查是否已存在
    if grep -q "^$port_input$" "$ALLOWED_PORTS_FILE" 2>/dev/null; then
        echo -e "${YELLOW}端口 $port_input 已在放行列表中${NC}"
        return 0
    fi
    
    # 添加到放行列表
    echo "$port_input" >> "$ALLOWED_PORTS_FILE"
    
    # 更新防火墙规则
    if [ -f "$CONFIG_DIR/ipv4_enabled" ]; then
        if [[ $port_input == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port_input"
            iptables -I INPUT 3 -p tcp --match multiport --dports $start_port:$end_port -j ACCEPT
            iptables -I INPUT 4 -p udp --match multiport --dports $start_port:$end_port -j ACCEPT
        else
            iptables -I INPUT 3 -p tcp --dport $port_input -j ACCEPT
            iptables -I INPUT 4 -p udp --dport $port_input -j ACCEPT
        fi
    fi
    
    if [ -f "$CONFIG_DIR/ipv6_enabled" ]; then
        if [[ $port_input == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port_input"
            ip6tables -I INPUT 3 -p tcp --match multiport --dports $start_port:$end_port -j ACCEPT
            ip6tables -I INPUT 4 -p udp --match multiport --dports $start_port:$end_port -j ACCEPT
        else
            ip6tables -I INPUT 3 -p tcp --dport $port_input -j ACCEPT
            ip6tables -I INPUT 4 -p udp --dport $port_input -j ACCEPT
        fi
    fi
    
    echo -e "${GREEN}✅ 已添加端口 $port_input 到放行列表${NC}"
    return 0
}

# 删除放行端口
delete_allowed_port() {
    echo -e "${BLUE}➖ 删除放行端口${NC}"
    
    view_allowed_ports
    
    echo -e "请输入要删除的端口号:"
    read port_input
    
    # 检查端口是否存在
    if ! grep -q "^$port_input$" "$ALLOWED_PORTS_FILE" 2>/dev/null; then
        echo -e "${RED}端口 $port_input 不在放行列表中${NC}"
        return 1
    fi
    
    # 从文件中删除
    sed -i "/^$port_input$/d" "$ALLOWED_PORTS_FILE"
    
    # 更新防火墙规则
    if [ -f "$CONFIG_DIR/ipv4_enabled" ]; then
        if [[ $port_input == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port_input"
            iptables -D INPUT -p tcp --match multiport --dports $start_port:$end_port -j ACCEPT
            iptables -D INPUT -p udp --match multiport --dports $start_port:$end_port -j ACCEPT
        else
            iptables -D INPUT -p tcp --dport $port_input -j ACCEPT
            iptables -D INPUT -p udp --dport $port_input -j ACCEPT
        fi
    fi
    
    if [ -f "$CONFIG_DIR/ipv6_enabled" ]; then
        if [[ $port_input == *-* ]]; then
            IFS='-' read -r start_port end_port <<< "$port_input"
            ip6tables -D INPUT -p tcp --match multiport --dports $start_port:$end_port -j ACCEPT
            ip6tables -D INPUT -p udp --match multiport --dports $start_port:$end_port -j ACCEPT
        else
            ip6tables -D INPUT -p tcp --dport $port_input -j ACCEPT
            ip6tables -D INPUT -p udp --dport $port_input -j ACCEPT
        fi
    fi
    
    echo -e "${GREEN}✅ 已从放行列表中删除端口 $port_input${NC}"
    return 0
}

# 删除 IPv4 海外入站
remove_ipv4_overseas() {
    echo -e "${BLUE}🗑️ 删除 IPv4 海外入站...${NC}"
    
    # 清除 iptables 规则
    iptables -F INPUT
    iptables -P INPUT ACCEPT
    
    # 删除 ipset
    ipset destroy $IPV4_IPSET_NAME
    
    # 删除标记文件
    rm -f "$CONFIG_DIR/ipv4_enabled"
    
    echo -e "${GREEN}✅ IPv4 海外入站已删除${NC}"
    return 0
}

# 删除 IPv6 海外入站
remove_ipv6_overseas() {
    echo -e "${BLUE}🗑️ 删除 IPv6 海外入站...${NC}"
    
    # 清除 ip6tables 规则
    ip6tables -F INPUT
    ip6tables -P INPUT ACCEPT
    
    # 删除 ipset
    ipset destroy $IPV6_IPSET_NAME
    
    # 删除标记文件
    rm -f "$CONFIG_DIR/ipv6_enabled"
    
    echo -e "${GREEN}✅ IPv6 海外入站已删除${NC}"
    return 0
}

# 删除并卸载
uninstall_all() {
    echo -e "${BLUE}🧹 删除并卸载...${NC}"
    
    # 删除 IPv4 规则
    if [ -f "$CONFIG_DIR/ipv4_enabled" ]; then
        remove_ipv4_overseas
    fi
    
    # 删除 IPv6 规则
    if [ -f "$CONFIG_DIR/ipv6_enabled" ]; then
        remove_ipv6_overseas
    fi
    
    # 禁用并删除服务
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable overseas_only_blocker.service
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    # 删除配置目录
    rm -rf "$CONFIG_DIR"
    
    echo -e "${GREEN}✅ OverseasOnlyBlocker 已完全卸载${NC}"
    return 0
}

# 验证防火墙规则
verify_firewall_rules() {
    echo -e "${BLUE}🔍 验证防火墙规则...${NC}"
    
    echo -e "${YELLOW}IPv4 防火墙规则:${NC}"
    iptables -L INPUT -v -n
    
    echo -e "\n${YELLOW}IPv6 防火墙规则:${NC}"
    ip6tables -L INPUT -v -n
    
    echo -e "\n${YELLOW}当前使用的 IP 集合:${NC}"
    ipset list
}

# 检查服务状态
check_service_status() {
    echo -e "${BLUE}🔍 检查服务状态...${NC}"
    
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}服务状态:${NC}"
        systemctl status overseas_only_blocker.service
    else
        echo -e "${YELLOW}OverseasOnlyBlocker 服务尚未安装${NC}"
    fi
    
    echo -e "\n${YELLOW}当前状态:${NC}"
    if [ -f "$CONFIG_DIR/ipv4_enabled" ]; then
        echo -e "${GREEN}✅ IPv4 海外入站: 已启用${NC}"
    else
        echo -e "${RED}❌ IPv4 海外入站: 未启用${NC}"
    fi
    
    if [ -f "$CONFIG_DIR/ipv6_enabled" ]; then
        echo -e "${GREEN}✅ IPv6 海外入站: 已启用${NC}"
    else
        echo -e "${RED}❌ IPv6 海外入站: 未启用${NC}"
    fi
}

# 显示菜单
show_menu() {
    echo -e "\n${PURPLE}============================================${NC}"
    echo -e "${PURPLE}       OverseasOnlyBlocker 2.0${NC}"
    echo -e "${PURPLE}============================================${NC}"
    echo -e "🌏 仅允许海外 IP 入站连接"
    echo -e "❌ 拒绝中国 IP 入站"
    echo -e "🌐 支持 IPv4 + IPv6"
    echo -e "🎯 支持端口范围放行"
    echo -e "${PURPLE}============================================${NC}"
    echo -e "${GREEN}1.${NC} 安装 IPv4 海外入站"
    echo -e "${GREEN}2.${NC} 安装 IPv6 海外入站"
    echo -e "${GREEN}3.${NC} 查看放行端口"
    echo -e "${GREEN}4.${NC} 添加放行端口"
    echo -e "${GREEN}5.${NC} 删除放行端口"
    echo -e "${GREEN}6.${NC} 删除 IPv4 海外入站"
    echo -e "${GREEN}7.${NC} 删除 IPv6 海外入站"
    echo -e "${GREEN}8.${NC} 删除并卸载"
    echo -e "${GREEN}9.${NC} 验证防火墙规则"
    echo -e "${GREEN}10.${NC} 检查服务状态"
    echo -e "${GREEN}0.${NC} 退出"
    echo -e "${PURPLE}============================================${NC}"
    echo -ne "请输入选项 [0-10]: "
}

# 主函数
main() {
    check_root
    check_environment
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                install_ipv4_overseas
                create_startup_script
                ;;
            2)
                install_ipv6_overseas
                create_startup_script
                ;;
            3)
                view_allowed_ports
                ;;
            4)
                add_allowed_port
                ;;
            5)
                delete_allowed_port
                ;;
            6)
                remove_ipv4_overseas
                ;;
            7)
                remove_ipv6_overseas
                ;;
            8)
                uninstall_all
                ;;
            9)
                verify_firewall_rules
                ;;
            10)
                check_service_status
                ;;
            0)
                echo -e "${GREEN}感谢使用 OverseasOnlyBlocker，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                ;;
        esac
        
        echo -e "${BLUE}按 Enter 键继续...${NC}"
        read
    done
}

# 执行主函数
main 
