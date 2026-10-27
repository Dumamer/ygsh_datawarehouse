#!/usr/bin/env bash
# =====================================================================
# hive-local.sh —— Windows 本地模式启动 Hive CLI（不依赖 Docker）
#
# 背景：课程方案用 Docker 跑 Hive，但本机 Windows 的「虚拟机平台」功能未开启
#      （Docker 引擎报 No virtualization available），因此改用 JDK8 + Hadoop +
#      Hive 的原生本地模式跑通全流程，详见 docs/环境搭建笔记.md。
#
# 原理：直接调用 Java 启动 org.apache.hadoop.hive.cli.CliDriver，
#      绕开 Linux 版 bin/hive 脚本在 Windows/Git Bash 下的路径转换问题；
#      Metastore 使用内嵌 Derby，无需单独部署 MySQL。
#
# 依赖目录（用环境变量覆盖）：
#   HIVE_HOME    Hive 3.1.3 解压目录
#   HADOOP_HOME  Hadoop 3.1.1 目录（bin 下需有 winutils.exe、hadoop.dll）
#   JAVA_HOME_8  JDK 8 目录
#
# 用法：
#   bash scripts/hive-local.sh -f sql/ods/create_ods.sql
#   bash scripts/hive-local.sh -e "show databases;"
# =====================================================================
set -u

HIVE_HOME="${HIVE_HOME:-D:/cxdownload/_setup/apache-hive-3.1.3-bin}"
HADOOP_HOME="${HADOOP_HOME:-D:/cxdownload/_setup/hadoop-3.1.1}"
JAVA_HOME_8="${JAVA_HOME_8:-D:/cxdownload/_setup/jdk8u504-b01}"

if [ ! -x "$JAVA_HOME_8/bin/java" ] && [ ! -f "$JAVA_HOME_8/bin/java.exe" ]; then
  echo "[错误] 未找到 JDK 8：$JAVA_HOME_8（Hive 3.1.3 不支持 JDK 17+，必须用 8 或 11）" >&2
  exit 1
fi

CP="$HIVE_HOME/conf;$HIVE_HOME/lib/*"
for d in common common/lib hdfs hdfs/lib yarn yarn/lib mapreduce mapreduce/lib tools/lib; do
  CP="$CP;$HADOOP_HOME/share/hadoop/$d/*"
done

# 阻止 MSYS 把参数里的 Windows 路径改写掉
export MSYS2_ARG_CONV_EXCL="*"
export HADOOP_HOME HADOOP_MAPRED_HOME="$HADOOP_HOME" HIVE_HOME
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"

# Git Bash 传进来的是 /d/xxx 形式，Java 不认，这里手工转成 Windows 路径
to_win() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -f|-i|--database)
      ARGS+=("$1"); shift
      [ $# -gt 0 ] && ARGS+=("$(to_win "$1")") && shift
      ;;
    --hiveconf)
      ARGS+=("$1"); shift
      if [ $# -gt 0 ]; then
        kv="$1"
        case "$kv" in
          *=/*) ARGS+=("${kv%%=*}=$(to_win "${kv#*=}")") ;;
          *)    ARGS+=("$kv") ;;
        esac
        shift
      fi
      ;;
    /*)
      ARGS+=("$(to_win "$1")"); shift
      ;;
    *)
      ARGS+=("$1"); shift
      ;;
  esac
done

exec "$JAVA_HOME_8/bin/java" -Xmx3g -XX:+UseG1GC \
  -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 \
  -Dhadoop.home.dir="$HADOOP_HOME" \
  -Dhive.home.dir="$HIVE_HOME" \
  -Djava.library.path="$HADOOP_HOME/bin" \
  -Dlog4j2.formatMsgNoLookups=true \
  -cp "$CP" \
  org.apache.hadoop.hive.cli.CliDriver "${ARGS[@]}"
