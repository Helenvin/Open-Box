#!/bin/sh
# 自有能力守卫:「一键生成故障转移组」必须还在。
#
# 为什么需要这道守卫(2026-09-16 拿上游 v0.1.200 的编译产物逐字节比对得来的):
#   上游**也有**故障转移,但只是骨架,而且是纯手动档 —— 主用页签只能放"一个固定的
#   节点或组",每个国家都得手动配一遍,维护成本极高。
#   证据:上游 panel/server/engine/user-groups.mjs、system/failover-manager.mjs、
#   api/groups.mjs 里 `groupRef` 出现 **0 次**、`故转` **0 次**;
#   我方 v2.06 同三个文件是 **6 / 7 / 3 次**。
#   上游 dist 里也没有 failoverModeGroup / groupAutoFailoverHint 这两个 i18n key。
#
#   我方多出来的这一层才是省事的关键:
#     - **一键生成**:勾选后按国家批量产出「<国家>-故转」组;
#     - **主用 = 「<国家>-手动」组**(引用分组,不是固定节点),备用 = 「<国家>-自动」组;
#     - 两个组由这一次操作一并建出来。
#   实现落点:
#     engine/user-groups.mjs(groupRef + 「故转」命名)、system/failover-manager.mjs(groupRef)、
#     前端 FailoverLaneCards.vue / FailoverLaneDetail.vue / store/openboxFailover.ts、
#     i18n key failoverModeGroup + groupAutoFailoverHint(三语)
#
#   威胁很具体:将来同步上游时若整块换掉面板,这一层会**静默消失**(上游产物里就没有
#   那两个 key,编译不报错、界面只是变回手动档),用户会莫名其妙地退回去一个个手配。
#   这道守卫拦的就是这个。
set -eu

fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "== 自有能力守卫:一键生成故障转移组(主用引用分组)必须在 =="

# 1) 服务端:一键生成 + 分组引用
has() { # <文件> <必须出现的字符串> <说明>
  if [ ! -f "$1" ]; then
    bad "$1 不存在"
    return 0
  fi
  if grep -q "$2" "$1"; then
    ok "$3"
  else
    bad "$3 —— $1 里找不到「$2」"
  fi
}
has panel/server/engine/user-groups.mjs 'groupRef' '一键生成:engine/user-groups.mjs 含 groupRef'
has panel/server/engine/user-groups.mjs '故转'      '一键生成:engine/user-groups.mjs 含「故转」命名'
has panel/server/system/failover-manager.mjs 'groupRef' '分组引用:failover-manager.mjs 含 groupRef'

# 2) 前端组件与 store
for f in \
  panel/src/components/proxies/FailoverLaneCards.vue \
  panel/src/components/proxies/FailoverLaneDetail.vue \
  panel/src/store/openboxFailover.ts ; do
  if [ -f "$f" ]; then ok "前端 $f"; else bad "前端 $f 丢失"; fi
done

# 3) 这两个 key 只属于我们 —— 上游那份产物里一个都没有
for locale in en zh zh-tw; do
  f="panel/src/i18n/$locale.ts"
  if [ ! -f "$f" ]; then
    bad "$f 不存在"
    continue
  fi
  for key in failoverModeGroup groupAutoFailoverHint; do
    if grep -q "$key" "$f"; then
      ok "i18n $locale.$key"
    else
      bad "i18n $locale 缺 key $key(丢了就等于退回手动档)"
    fi
  done
done

# 4) 契约测试
for f in panel/server/engine/user-groups.test.mjs panel/server/system/failover-manager.test.mjs ; do
  if [ -f "$f" ]; then ok "测试 $f"; else bad "测试 $f 丢失"; fi
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

== 守卫失败:一键生成故障转移组的能力被改动/覆盖了 ==
上游 v0.1.200 的故障转移是纯手动档:主用页签只能放一个固定的节点/组,每个国家手配一遍。
「一键按国家生成 <国家>-故转 组 + 主用引用 <国家>-手动 组」是本仓库独有的这一层,
也是这个项目最省事的地方。要动它之前先读本脚本头部的对比数据与落点清单。
EOF
  exit 1
fi

echo "== 守卫通过:一键生成故障转移组仍在 =="
