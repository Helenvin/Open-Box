#!/bin/sh
# 内核口径守卫:Open-Box 的内核必须由本仓库自建,并钉在 tcp2。
#
# 为什么必须钉住(2026-09-16 实测):
#   1) 面板的「故障转移」(panel/server/system/failover-manager.mjs) 建立在 tcp2 那版
#      http-latency 行为之上。换成上游内核后,故障转移集成测试当场失败(期望切到备用
#      页签、实际停在主用)。
#   2) 上游内核已迭代到 1.14.0-openbox-tcp5,但 **tcp3 起的补丁从未公开**:
#      上游仓库 v0.1.200 的 tag 下只有 16 个文件,scripts/singbox-tcp-dns-hotfix/
#      整个不存在。没有 diff 对象 => 无法移植,只能自建。
#   3) 让掉的只是 tcp3 起加的「探测去重」(probe_coordinator),属省探测请求的优化,
#      不影响选路正确性。sing-box 本体两边都还是 1.14.0,不存在安全版本缺口。
#
# 这个脚本失败 = 有人(包括未来的我)把内核换成了上游预编译件,或把它写进了
# 组件采购表。除非 .github/workflows/kernel-compat.yml 探针证明上游内核下故障转移
# 全绿,否则不要动它。
set -eu

EXPECTED_SUFFIX="${EXPECTED_KERNEL_SUFFIX:--openbox-tcp2}"
KERNEL_DIR="scripts/singbox-tcp-dns-hotfix"
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "== 内核口径守卫:内核必须自建并钉 tcp2(期望后缀 $EXPECTED_SUFFIX)=="

# 1) 版本号必须仍是本仓库自建的 tcp2
if [ -f "$KERNEL_DIR/versions.sh" ]; then
  SINGBOX_VERSION=$(sed -n 's/^SINGBOX_VERSION="\(.*\)"$/\1/p' "$KERNEL_DIR/versions.sh" | head -1)
  if [ -z "$SINGBOX_VERSION" ]; then
    bad "$KERNEL_DIR/versions.sh 里读不到 SINGBOX_VERSION"
  else
    case "$SINGBOX_VERSION" in
      *"$EXPECTED_SUFFIX") ok "SINGBOX_VERSION=$SINGBOX_VERSION" ;;
      *) bad "SINGBOX_VERSION=$SINGBOX_VERSION 不含后缀 $EXPECTED_SUFFIX —— 内核被换掉了?" ;;
    esac
  fi
  if sed -n 's/^SINGBOX_SOURCE_SHA256="\(.*\)"$/\1/p' "$KERNEL_DIR/versions.sh" | grep -Eq '^[0-9a-f]{64}$'; then
    ok "上游 sing-box 源码已钉 sha256"
  else
    bad "SINGBOX_SOURCE_SHA256 缺失或不是 64 位 hex —— 源码输入没被钉住"
  fi
else
  bad "$KERNEL_DIR/versions.sh 不存在 —— 内核已不再由本仓库构建"
fi

# 2) 内核构建输入必须齐全:那两个 patch 就是「tcp2 行为」的载体
for f in build.sh toolchain.sh http-latency.patch tcp-dns-short-connections.patch; do
  if [ -f "$KERNEL_DIR/$f" ]; then
    ok "内核构建输入 $KERNEL_DIR/$f"
  else
    bad "内核构建输入 $KERNEL_DIR/$f 丢失"
  fi
done

# 3) 故障转移的实现和它的契约测试必须都在(测试就是"内核行为没变"的证明)
for f in \
  panel/server/api/failover.mjs \
  panel/server/system/failover-manager.mjs \
  panel/server/system/failover-manager.test.mjs \
  panel/server/system/http-latency.integration.test.mjs \
  panel/src/store/openboxFailover.ts ; do
  if [ -f "$f" ]; then
    ok "在 $f"
  else
    bad "丢失 $f"
  fi
done

# 4) 将来若引入「上游组件采购表」(组件化发版),kernel 必须不在其中
found_table=0
for t in scripts/upstream-components.sh scripts/upstream-components.json; do
  [ -f "$t" ] || continue
  found_table=1
  if grep -Eiq '(^|[^a-z])kernel([^a-z]|$)' "$t"; then
    bad "$t 里出现了 kernel —— 上游内核会破坏故障转移,内核只能自建"
  else
    ok "$t 未采购 kernel"
  fi
done
if [ "$found_table" -eq 0 ]; then
  ok "暂无上游组件采购表(单体包口径) —— 内核天然自建"
fi

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

== 守卫失败:内核口径被改动 ==
要改成「采购上游内核」之前,先把这两步走完:
  1) 读本脚本头部的注释,它记录了为什么不能这么做;
  2) 跑 .github/workflows/kernel-compat.yml 探针 —— 同一个 job 里用本仓库内核和
     上游预编译内核各跑一遍故障转移集成测试。
只有探针证明「上游内核下故障转移全绿」,才谈得上解除这条守卫。
EOF
  exit 1
fi

echo "== 守卫通过:内核仍是本仓库自建的 tcp2 =="
