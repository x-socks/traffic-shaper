# TrafficLimitAvoid 智能流量控制系统

一个系统级的智能流量控制解决方案，帮助避开VPS限速策略。适用于所有网络传输场景，不限于特定应用或下载任务。

## 功能特点

- **避开常见VPS限速策略**：
  - 连续下载超过5GB流量触发限速
  - 占用带宽超过50Mbps达5分钟以上触发限速

- **智能流量管理**：
  - 实时监控网络流量和带宽使用情况
  - 动态调整带宽上限，避免触发限速
  - 自动暂停和恢复机制，规避限速策略

- **系统级集成**：
  - 作为systemd服务在后台运行
  - 完全透明，无需修改现有应用程序
  - 自动启动，自动恢复，无需人工干预

## 系统要求

- Linux操作系统
- root权限
- 必要的软件包：
  - `iproute2`（提供tc命令）
  - `ifstat`（带宽监控工具）
  - `iptables`（网络流量控制）
  - `bc`（数学计算工具）

## 安装步骤

### 1. 下载脚本文件

首先，在您的VPS上创建脚本文件：

```bash
sudo nano /usr/local/bin/traffic-shaper.sh
```

将`traffic-shaper.sh`的内容复制到此文件中。

### 2. 设置执行权限

```bash
sudo chmod +x /usr/local/bin/traffic-shaper.sh
```

### 3. 设置系统服务

创建systemd服务配置文件：

```bash
sudo nano /etc/systemd/system/traffic-shaper.service
```

将`traffic-shaper.service`的内容复制到此文件中。

### 4. 配置脚本参数

编辑`/usr/local/bin/traffic-shaper.sh`文件，调整以下参数：

```bash
INTERFACE="eth0"                # 修改为您的网络接口名称
MAX_BANDWIDTH=48                # 带宽上限(Mbps)
BANDWIDTH_TIME_LIMIT=300        # 带宽时间限制(秒)
MAX_CONTINUOUS_DATA=4800        # 连续流量限制(MB)
PAUSE_DURATION=180              # 暂停时间(秒)
MONITOR_INTERVAL=5              # 监控间隔(秒)
```

特别注意：您需要将`INTERFACE`参数修改为您VPS上的实际网络接口名称。可以通过运行`ip addr`命令查看您的网络接口名称。

### 5. 安装依赖包

```bash
# Debian/Ubuntu系统
sudo apt update
sudo apt install iproute2 ifstat iptables bc

# CentOS/RHEL系统
sudo yum install iproute ifstat iptables bc
```

### 6. 启用并启动服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable traffic-shaper.service
sudo systemctl start traffic-shaper.service
```

## 使用方法

### 查看服务状态

```bash
sudo systemctl status traffic-shaper.service
```

### 查看日志

```bash
# 查看服务日志
sudo journalctl -u traffic-shaper.service

# 查看脚本详细日志
sudo cat /var/log/traffic-shaper.log
```

### 停止服务

```bash
sudo systemctl stop traffic-shaper.service
```

### 重新启动服务

```bash
sudo systemctl restart traffic-shaper.service
```

### 禁用服务

如果您想禁用服务，使其不再自动启动：

```bash
sudo systemctl disable traffic-shaper.service
```

## 工作原理

1. **初始化**：脚本使用Linux的tc工具设置分层令牌桶(HTB)队列规则，限制网络接口的最大带宽
2. **监控**：持续监控网络流量和带宽使用情况
3. **智能响应**：
   - 当检测到接近连续流量限制时，暂停网络活动并重置计数器
   - 当检测到持续高带宽使用时，跟踪持续时间并在接近限制时主动暂停
   - 动态调整带宽上限，避免长时间接近阈值

## 故障排除

### 服务无法启动

1. 检查依赖项是否已安装：
   ```bash
   which tc ifstat iptables bc
   ```

2. 检查网络接口名称是否正确：
   ```bash
   ip addr
   ```
   然后修改脚本中的`INTERFACE`参数

3. 检查日志文件：
   ```bash
   sudo journalctl -u traffic-shaper.service
   ```

### 网络异常

如果您的网络完全停止工作，可能是因为脚本在暂停状态下意外终止。运行以下命令恢复：

```bash
sudo iptables -D OUTPUT -j DROP
```

## 高级定制

### 调整带宽参数

如果您的VPS有不同的限速策略，可以修改脚本中的以下参数：

```bash
MAX_BANDWIDTH=48                # 调整为略低于您VPS的限速阈值
BANDWIDTH_TIME_LIMIT=300        # 调整为您VPS的时间限制
MAX_CONTINUOUS_DATA=4800        # 调整为略低于您VPS的流量限制
```

### 添加例外规则

如果您希望某些流量不受限制，可以修改脚本，添加iptables例外规则：

```bash
# 允许特定IP地址不受限制
iptables -A OUTPUT -d 特定IP地址 -j ACCEPT

# 允许特定端口不受限制
iptables -A OUTPUT -p tcp --dport 特定端口 -j ACCEPT
```

## 安全注意事项

- 此脚本需要root权限运行，请确保从可信来源获取
- 定期检查日志文件，确保系统正常运行
- 如果您的VPS提供商禁止使用流量控制工具，请检查您的服务条款

## 许可

此脚本供个人学习和使用，请遵守您的VPS服务提供商的服务条款。

## 免责声明

本脚本仅供学习和研究目的使用。作者不对使用此脚本可能导致的任何服务中断、账户停用或其他问题负责。请在使用前了解您的VPS提供商的服务条款。
