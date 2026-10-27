# 环境启动说明（Docker 方案）

> 这是课程《第 1 周部署操作手册》给出的标准方案。文件已按手册重写并补全了
> 手册里省略的两处关键点：**Metastore schema 初始化** 和 **MySQL 健康检查**。

## 1. 前置

- 安装 Docker Desktop for Windows，安装时勾选 **WSL 2 backend**
- 确认已开启 Windows 功能：`虚拟机平台` + `适用于 Linux 的 Windows 子系统`
  （PowerShell 管理员执行，之后**必须重启**）
  ```powershell
  dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
  dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
  ```
- 验证：
  ```bash
  docker --version
  docker compose version
  docker info            # 能看到 Server Version 才算引擎真的起来了
  ```

## 2. 启动

```bash
cd docker
docker compose up -d
docker compose ps
```

预期状态：

| 容器 | 状态 |
|---|---|
| ydsh-mysql | running (healthy) |
| ydsh-schematool | **Exited (0)** ← 一次性初始化任务，正常完成即退出 |
| ydsh-hive-metastore | running |
| ydsh-hive-server | running |

如果 `hive-metastore` / `hive-server` 反复重启，按顺序排查：

```bash
docker logs ydsh-schematool         # schema 是否初始化成功
docker logs ydsh-hive-metastore     # 连不上 mysql？驱动缺失？
docker logs ydsh-hive-server
```

## 3. 验证可用

```bash
docker exec -it ydsh-hive-server beeline -u jdbc:hive2://localhost:10000 -n hive
```
```
show databases;
create database if not exists ydsh_ods;
```

## 4. 跑本周脚本

```bash
# 在宿主机执行（推荐，方便看日志）
bash ../scripts/run_all.sh
```

或进入容器执行：

```bash
docker exec -it ydsh-hive-server bash
hive -f /sql/ods/create_ods.sql
hive --hiveconf data_dir=/data -f /sql/ods/load_ods.sql
```

## 5. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 容器启动后立即退出 | Metastore 未就绪 / schema 未初始化 | 先看 `ydsh-schematool` 日志，确认 Exited 0 |
| `10000 端口被占用` | 已有进程监听 | `netstat -ano \| findstr 10000` 找到 PID 后改映射端口 |
| Metastore 连不上 MySQL | 连接串写成 localhost | 必须写服务名 `mysql`（见 `hive-conf/hive-site.xml`） |
| `Public Key Retrieval is not allowed` | MySQL 8 认证方式 | 连接串加 `allowPublicKeyRetrieval=true`（已加） |
| 中文乱码 | 容器字符集 | MySQL 启动参数已设 `utf8mb4` |

## 6. 停止与清理

```bash
docker compose down            # 停止并删除容器
docker compose down -v         # 连同数据卷一起删除（会丢 Metastore 数据，慎用）
```
