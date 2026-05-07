# oneinstack

自用的 Nginx-only 源码安装与升级工具。

这个仓库不是通用 Web 环境安装器，也不是上游同步仓库。维护目标只有一个：在新装或最小化安装的 Linux 系统上，安装、升级和管理一套标准 Nginx。PHP、数据库、Apache、Tomcat、Caddy、FTP、Redis、Memcached、phpMyAdmin 等非目标栈不再维护，也不会在默认流程中安装。

## 当前目标

- 只安装标准 Nginx。
- 保留根目录常用入口：
  - `install.sh`
  - `upgrade.sh`
  - `vhost.sh`
- 保留 `acme.sh` / Let's Encrypt 证书申请能力。
- Nginx 使用 PCRE2。
- Nginx 编译保留 HTTP/3 模块：`--with-http_v3_module`。
- 默认生成的站点配置不主动启用 QUIC / HTTP/3 `listen` 指令。
- 升级 Nginx 时只替换二进制，不覆盖现有运行配置。

## 目录结构

```text
.
├── install.sh              # 标准 Nginx 安装入口
├── upgrade.sh              # Nginx 二进制升级入口
├── vhost.sh                # 静态站点 / 反向代理 / SSL 辅助入口
├── lib/                    # 安装、下载、检测、编译、升级辅助脚本
├── services/               # systemd 服务模板
├── templates/nginx/        # Nginx 默认配置与站点模板
├── downloads/              # 源码包与临时编译目录，本地缓存，不作为源码维护重点
├── options.conf            # 本机安装参数
└── versions.txt            # 组件版本定义
```

## 当前组件版本

以 `versions.txt` 为准。当前主要目标为：

```text
Nginx   1.30.0
OpenSSL 3.6.1
PCRE2   10.47
jemalloc 5.3.1
```

## 安装 Nginx

```bash
cd /opt/oneinstack
./install.sh
```

安装脚本会强制走标准 Nginx 路径：

- `nginx_option=1`
- 不安装 Apache / PHP / 数据库 / Tomcat / Caddy / Node.js / FTP / Redis / Memcached / phpMyAdmin
- 安装必要基础依赖
- 编译安装 Nginx、OpenSSL、PCRE2、jemalloc
- 安装 systemd 服务文件

Nginx 默认安装目录来自 `options.conf`，当前为：

```text
/usr/local/nginx
```

## 升级 Nginx

升级入口：

```bash
cd /opt/oneinstack
./upgrade.sh --nginx
```

指定版本：

```bash
./upgrade.sh --nginx 1.30.0
# 或
./upgrade.sh --nginx=1.30.0
```

不带版本时使用 `versions.txt` 中的 `nginx_ver`。

升级策略是二进制替换，不执行 `make install`，不会覆盖：

```text
/usr/local/nginx/conf/nginx.conf
/usr/local/nginx/conf/vhost/*
/usr/local/nginx/conf/ssl/*
```

也不会主动清理站点目录、日志、证书或已有 vhost 配置。

实际流程：

1. 读取当前 `nginx -V` 编译参数。
2. 将 OpenSSL 参数改写到当前目标版本。
3. 将 PCRE 参数改写到 PCRE2 当前目标版本。
4. 保留或补充 `--with-http_v3_module`。
5. 编译新 Nginx。
6. 用新二进制测试现有 `nginx.conf`。
7. 将新二进制 staging 到临时文件。
8. 把旧二进制重命名为时间戳备份。
9. 将 staged 新二进制重命名到正式路径。
10. 再次运行 `nginx -t`。
11. 运行中服务走 `USR2` 热升级并退出 oldbin；未运行则 `systemctl restart nginx`。
12. 任一步失败则回滚旧二进制。

这个流程已经在本机真实验证：从 `nginx/1.29.8 + OpenSSL 4.0.0` 升级到 `nginx/1.30.0 + OpenSSL 3.6.1`，保留 HTTP/3 编译模块，并保持现有配置不被覆盖。

## 管理站点

```bash
cd /opt/oneinstack
./vhost.sh
```

当前 `vhost.sh` 只维护 Nginx 相关能力：

- 静态站点
- 反向代理站点
- HTTP vhost 配置生成
- HTTPS vhost 配置生成
- Let's Encrypt / `acme.sh` 证书申请
- DNS API 证书申请入口

HTTP-01 证书申请会先生成并 reload 临时 HTTP 配置，确保验证目录可访问后再签发证书。

## IP 检测

仓库不再携带未知静态辅助二进制。

原来的 `ois.*` 行为已改为 shell 实现：

- 本机 IPv4：`ip -4 a show scope global`
- fallback：`ifconfig`
- 公网 IPv4：`curl -4fsS --max-time 5 https://ip.sb`

实现位置：

```text
lib/ip.sh
```

## HTTP/3 说明

本仓库的策略是：

- 编译层面保留 HTTP/3：`--with-http_v3_module`
- 默认配置层面不主动启用 QUIC / HTTP/3 listen

原因很简单：HTTP/3 是否启用取决于证书、UDP 暴露、防火墙、反向代理链路和业务兼容性，不应该由默认 vhost 模板替用户强开。

需要启用时，在具体站点配置中手动添加对应 QUIC / HTTP/3 配置。

## 校验命令

修改脚本后至少跑：

```bash
cd /opt/oneinstack
bash -n install.sh upgrade.sh vhost.sh lib/*.sh
shellcheck -S error install.sh upgrade.sh vhost.sh lib/*.sh
git diff --check
```

检查当前 Nginx：

```bash
/usr/local/nginx/sbin/nginx -V
/usr/local/nginx/sbin/nginx -t
systemctl status nginx --no-pager
```

## 维护边界

这个仓库按自用 Nginx 工具箱维护：

- 优先保证安装、升级、vhost、SSL 这几条真实路径稳定。
- 优先使用官方或项目发布源下载源码包。
- 不追求兼容完整 OneinStack 历史功能。
- 不恢复 PHP、数据库、Apache、Tomcat、Caddy 等非目标栈。
- 不保留来源不清的静态二进制工具。
- 配置安全性优先于“自动帮你开启所有特性”。
