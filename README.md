# OverseasOnlyBlocker 2.0

🌏 一个用于管理服务器入站连接的防火墙脚本，支持仅允许海外 IP 访问指定端口。

## 特性

- 🚫 可选择性地阻止中国 IP 访问指定端口
- ✨ 默认不封禁任何端口，只有添加到放行列表的端口才会阻止中国IP访问
- 🌐 同时支持 IPv4 和 IPv6
- 🎯 支持端口范围配置（例如：8000-9000）
- 🔄 支持开机自启动
- 📝 完整的日志记录
- 🎨 彩色的交互式界面

## 一键安装

```bash
# 国外服务器使用以下命令：
wget -O overseas_only_blocker.sh https://raw.githubusercontent.com/Cd1s/cninblock/refs/heads/main/overseas_firewall.sh && chmod +x overseas_only_blocker.sh && sudo ./overseas_only_blocker.sh
```

## 使用说明

### 主菜单选项

1. 安装 IPv4 海外入站 - 启用 IPv4 防火墙规则
2. 安装 IPv6 海外入站 - 启用 IPv6 防火墙规则
3. 查看放行端口 - 显示当前配置的端口列表
4. 添加放行端口 - 添加新的端口（这些端口将只允许海外IP访问）
5. 删除放行端口 - 移除已配置的端口
6. 删除 IPv4 海外入站 - 删除 IPv4 防火墙规则
7. 删除 IPv6 海外入站 - 删除 IPv6 防火墙规则
8. 删除并卸载 - 完全卸载所有规则和配置
9. 验证防火墙规则 - 查看当前防火墙规则
10. 检查服务状态 - 查看服务运行状态

### 使用示例

1. 只允许海外IP访问网站（80,443端口）：
```bash
sudo ./overseas_only_blocker.sh
# 选择选项 1 安装 IPv4 规则
# 选择选项 4 添加端口，输入 80
# 再次选择选项 4，输入 443
```

2. 允许海外IP访问一个端口范围：
```bash
sudo ./overseas_only_blocker.sh
# 选择选项 4
# 输入端口范围，例如：8000-9000
```

3. 查看当前规则：
```bash
sudo ./overseas_only_blocker.sh
# 选择选项 9
```

## 工作原理

- 默认情况下，所有端口都是开放的，允许所有IP访问
- 当您将端口添加到"放行列表"时，该端口将只允许海外IP访问（阻止中国IP）
- 不在放行列表中的端口保持完全开放状态（允许所有IP访问）
- 使用 ipset 维护中国 IP 地址列表
- 使用 iptables/ip6tables 进行端口控制
- 支持开机自动恢复规则

## 注意事项

1. 脚本需要 root 权限运行
2. 默认会放行 22 端口（SSH），以防止被锁定
3. 确保服务器已安装以下依赖：
   - ipset
   - iptables
   - wget
4. 如果您在使用云服务器，请确保云服务商的防火墙/安全组规则已正确配置

## 常见问题

Q: 如何确认规则是否生效？  
A: 使用选项 9 "验证防火墙规则" 查看当前规则，或者尝试从中国和海外分别访问配置的端口。

Q: 如何修改已添加的端口？  
A: 先使用选项 5 删除旧端口，然后使用选项 4 添加新端口。

Q: 忘记添加了哪些端口？  
A: 使用选项 3 "查看放行端口" 可以查看所有已配置的端口。

## 卸载方法

```bash
sudo ./overseas_only_blocker.sh
# 选择选项 8 即可完全卸载
```

## 更新日志

### v2.0
- 新增：默认不封禁功能，只对放行列表中的端口进行控制
- 新增：IPv6 支持
- 优化：规则管理逻辑
- 优化：安装流程
- 优化：错误处理

### v1.0
- 初始版本发布

## 许可证

MIT License

## 致谢

- [china_ip_list](https://github.com/17mon/china_ip_list) - 提供中国IP地址列表
- [APNIC](https://www.apnic.net/) - 提供备用IP地址数据 
