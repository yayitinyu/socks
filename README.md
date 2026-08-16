# Linux VPS SOCKS5 一键节点

这是一个基于 [Dante](https://www.inet.no/dante/) 的 SOCKS5 安装脚本。它会随机选择空闲高位端口、生成强随机凭据、创建 systemd 服务，并自动适配 VPS 上已经启用的防火墙。

## 功能

- 默认**仅 IPv4 出口**，可用 `--dual-stack` 切换为 IPv4 + IPv6 双栈出口
- 默认从 `20000-60000` 随机选择未监听的 TCP 端口
- 随机生成独立的 SOCKS5 用户名与密码
- 支持 Debian、Ubuntu、RHEL、Rocky Linux、AlmaLinux、CentOS Stream 和 Fedora 的常见 systemd 环境
- 自动适配已启用的 UFW、firewalld、iptables/ip6tables 或 nftables
- 在启用 SELinux 的系统上自动管理 `socks_port_t` 端口标签和文件上下文
- 不会自动启用原本关闭的防火墙，避免意外中断 SSH
- 默认阻止访问 IPv4 与 IPv6 的环回、内网、链路本地、云元数据和保留地址
- 配置校验、服务监听检查、正误密码握手检查与真实 SOCKS5 出口自检
- 支持安全查看安装信息和完整卸载

脚本默认只开放 SOCKS5 的 TCP `CONNECT` 命令，适用于浏览器、下载工具和大多数应用代理场景，不提供 UDP Associate。

## 一键安装

### 通用 Linux（Debian / Ubuntu / RHEL / Rocky / Fedora 等 systemd 环境）

**1. 默认随机端口（20000-60000）一键安装：**

```bash
curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5.sh | sudo bash
```

**2. 自定义指定端口（例如指定端口 35678）：**

```bash
curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5.sh | sudo bash -s -- --port 35678
```

也可通过环境变量指定端口：

```bash
curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5.sh | sudo PORT=35678 bash
```

**3. 限制只允许指定公网 IP 连接：**

```bash
curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5.sh \
  | sudo bash -s -- --port 35678 --allow-cidr 203.0.113.8/32
```

---

### Alpine Linux（OpenRC 环境）

Alpine 默认通常直接以 `root` 登录且未预装 `sudo`，直接执行即可：

**1. 默认随机端口（20000-60000）一键安装：**

```bash
apk add --no-cache curl bash && curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh | bash
```

若使用 `wget`：

```bash
apk add --no-cache wget bash && wget -qO- https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh | bash
```

**2. 自定义指定端口（例如指定端口 35678）：**

```bash
apk add --no-cache curl bash && curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh \
  | bash -s -- --port 35678
```

也可通过环境变量指定端口：

```bash
apk add --no-cache curl bash && curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh \
  | PORT=35678 bash
```

**3. NAT VPS（NAT 小鸡）指定入口 IP / 域名与映射端口：**

```bash
apk add --no-cache curl bash && curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh \
  | bash -s -- --port 35678 --host nat.example.com
```

**4. 限制只允许指定客户端公网 IP 连接：**

```bash
apk add --no-cache curl bash && curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh \
  | bash -s -- --port 35678 --allow-cidr 203.0.113.8/32
```

安装完成后会输出地址、端口、用户名、密码和 `socks5h://` 连接串。凭据也会以仅 root 可读的权限保存到 `/etc/socks5-node/state.env`，便于之后查看。Dante 配置单独放在 `/etc/socks/socks5-node.conf`。

## 自定义安装

通用 Linux：

```bash
sudo bash socks5.sh install \
  --port 35678 \
  --host nat.example.com \
  --username myproxy \
  --password 'ReplaceWithStrongPassword123' \
  --allow-cidr 203.0.113.8/32
```

Alpine Linux：

```bash
bash socks5_alpine.sh install \
  --port 35678 \
  --host nat.example.com \
  --username myproxy \
  --password 'ReplaceWithStrongPassword123' \
  --allow-cidr 203.0.113.8/32
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `-p, --port PORT` | 指定 `1025-65535` 范围内的端口 |
| `-H, --host HOST` | 指定客户端连接入口地址（IPv4 / IPv6 或域名，用于 NAT 小鸡等场景） |
| `-u, --username USER` | 指定新建的 SOCKS5 系统用户名 |
| `-P, --password PASS` | 指定 12-128 位安全字符密码 |
| `--allow-cidr CIDR` | 只允许一个 IPv4 或 IPv6 地址/网段连接；默认 `0/0`（放行全部来源） |
| `--dual-stack` | 出口启用 IPv4 + IPv6 双栈转发；默认仅使用 IPv4 出口 |
| `--allow-private` | 允许代理访问 VPS 所在的私网和链路本地地址 |
| `--no-firewall` | 完全不修改操作系统防火墙 |
| `-f, --force` | 覆盖已有的旧节点安装并应用新参数 |

安装完成后，系统会自动配置 `socks5-node` 快捷管理命令。如果已安装节点，再次运行无参数安装命令只会恢复并显示现有服务。若需使用新参数更换端口或凭据，可直接添加 `-f / --force` 参数覆盖重装，或先卸载后再安装。

## 管理

安装后可在系统任意目录下直接执行 `socks5-node` 命令进行管理：

### 本地快捷管理

查看节点信息：

```bash
socks5-node info
```

卸载节点：

```bash
socks5-node uninstall
```

自动化或免确认卸载：

```bash
socks5-node uninstall --yes
```

### 服务与日志查看

- **通用 Linux (systemd)**：
  ```bash
  systemctl status socks5-node --no-pager
  journalctl -u socks5-node -f
  ```
- **Alpine Linux (OpenRC)**：
  ```bash
  rc-service socks5-node status
  tail -f /var/log/socks5-node.log
  ```

### 远程一键卸载（无需本地保存脚本）

- **通用 Linux**：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5.sh | sudo bash -s -- uninstall --yes
  ```
- **Alpine Linux**：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/yayitinyu/socks/main/socks5_alpine.sh | bash -s -- uninstall --yes
  ```

卸载会删除本脚本创建的服务、防火墙规则、凭据和托管账号，但会保留发行版安装的 Dante 软件包，避免误删其他程序的依赖。

## 出口协议栈说明

客户端使用 `socks5h://` 时，目标域名由 VPS 上的 Dante 解析。在双栈机器上，glibc 按 RFC 6724 把 AAAA 排在前面，Dante 就会优先用 IPv6 出站，导致目标网站看到的全是 VPS 的 IPv6 地址。

因此脚本默认只使用 IPv4 出口：

- **默认（仅 IPv4）**：生成 `external.protocol: ipv4`，出口固定走 IPv4，目标网站看到的是 VPS 的 IPv4 地址。
- **`--dual-stack`**：不加协议族限制，IPv4 / IPv6 出口都可用，具体走哪个由目标域名的解析结果决定（双栈目标通常是 IPv6）。
- 未检测到 IPv4 默认路由时（纯 IPv6 小鸡），脚本会自动回退为双栈出口并给出提示。

需要注意，[Dante 只支持协议族的包含与排除，没有优先级机制](https://www.inet.no/dante/doc/1.4.x/config/ipv6.html)，所以无法配置成「IPv4 优先、IPv6 兜底」。若确实需要该行为，只能在系统层面调整 `/etc/gai.conf`（`precedence ::ffff:0:0/96 100`），但那会影响整台机器的域名解析顺序，本脚本不会自动修改。

`external.protocol` 需要 Dante 1.4.1 及以上版本；在更老的 Dante 上，脚本会退回到把出口固定为出口网卡的 IPv4 地址，效果相同。

入站监听始终是 IPv4 通配（`internal: 0.0.0.0`），`--dual-stack` 只影响出口方向。

## 防火墙说明

脚本只管理 VPS 操作系统内部的防火墙：

- UFW：添加带 `socks5-node-端口` 注释的 TCP 规则
- firewalld：在出口网卡所属 zone 放行端口或来源受限的 rich rule（支持 IPv4 / IPv6）
- iptables/ip6tables/nftables：添加带唯一注释的规则，并通过系统服务在重启后恢复
- 未检测到活动防火墙：不做修改，因为此时系统本身没有阻止该端口

入站放行规则跟随出口模式：默认（仅 IPv4）只放行 IPv4，`--dual-stack` 时同时放行 IPv4 与 IPv6；使用 `--allow-cidr` 指定单一协议族的网段时，只放行对应协议族。卸载时两种协议族的残留规则都会被清理。

启用 SELinux 时（如 RHEL/Fedora），脚本不会关闭或切换到 Permissive 模式，而是为随机端口添加精确的 `socks_port_t` 本地映射；卸载时只删除本脚本创建的映射。若目标端口已有其他本地 SELinux 映射，脚本会换一个随机端口或拒绝覆盖用户指定端口。

AWS Security Group、Google Cloud Firewall、Azure NSG、Oracle Cloud Security List 等云厂商外层防火墙无法由通用 VPS 脚本安全修改。如果服务正在监听但外部无法连接，请在服务商控制台放行输出端口的 TCP 入站流量。

## 安全注意事项

SOCKS5 的用户名/密码认证和代理流量本身**不提供传输加密**。凭据会阻止匿名滥用，但不能替代 TLS、SSH 隧道或 VPN。建议：

- 使用 `--allow-cidr` 限制客户端公网 IP
- 不要通过代理传输未使用 HTTPS/TLS 保护的敏感数据
- 不需要访问私网时保留默认的私网目标拦截
- 定期检查日志中的异常连接

## 本地校验

```bash
bash -n socks5.sh
bash -n socks5_alpine.sh
bash tests/test.sh
```

Windows 上的静态测试无法证明真实 Linux VPS 的服务管理器、防火墙、系统密码认证与公网安全组行为；正式使用前应在目标发行版 VPS 上完成一次实际连接测试。

