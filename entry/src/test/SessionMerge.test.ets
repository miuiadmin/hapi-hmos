// SessionMerge 纯逻辑单测 —— 会话列表就地合并（mergeSessionArrays）
//
// 根因背景：列表 ForEach 同 key 复用项时，整体替换数组为新对象实例 → ForEach 视 key 不变 →
//   不重调 itemGenerator → 标题/状态点冻结在首帧（须重启 App 才更新）。mergeSessionArrays 以 id 为键
//   复用既有 @ObservedV2 对象 + copyFrom 改 @Trace 字段，触发字段级重渲染。
//
// 覆盖：同 id 复用对象引用 + 字段更新 / 新增入列 / 删除丢弃 / 顺序跟随 fetched。

import { describe, it, expect } from '@ohos/hypium';
import { SessionSummary, mergeSessionArrays } from '../main/ets/models/Types';

// 最小可用会话快照（id + updatedAt）。
function mk(id: string, updatedAt: number): SessionSummary {
  const s = new SessionSummary();
  s.id = id;
  s.updatedAt = updatedAt;
  s.thinking = false;
  return s;
}

export default function sessionMergeTest(): void {
  describe('mergeSessionArrays — 就地合并', () => {
    it('同 id 复用既有对象引用（非新实例）+ copyFrom 改字段', 0, () => {
      const a = mk('s1', 1000);
      a.thinking = false;
      const existing: SessionSummary[] = [a];
      const fetched: SessionSummary[] = [mk('s1', 2000)];
      fetched[0].thinking = true;
      const out = mergeSessionArrays(existing, fetched);
      expect(out.length).assertEqual(1);
      expect(out[0] === a).assertTrue();          // 同一对象引用（ForEach 保留项）
      expect(out[0].updatedAt).assertEqual(2000); // 字段已 copyFrom 更新
      expect(out[0].thinking).assertTrue();
    });
    it('新增会话入列（既有无此 id）', 0, () => {
      const out = mergeSessionArrays([], [mk('s2', 1)]);
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('s2');
    });
    it('删除会话丢弃（fetched 无此 id）', 0, () => {
      const existing: SessionSummary[] = [mk('s1', 1), mk('s2', 2)];
      const out = mergeSessionArrays(existing, [mk('s2', 2)]);
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('s2');
    });
    it('顺序跟随 fetched', 0, () => {
      const existing: SessionSummary[] = [mk('a', 1)];
      const out = mergeSessionArrays(existing, [mk('b', 2), mk('a', 3)]);
      expect(out.length).assertEqual(2);
      expect(out[0].id).assertEqual('b');
      expect(out[1].id).assertEqual('a');
    });
    it('空 fetched → 空结果', 0, () => {
      const out = mergeSessionArrays([mk('a', 1)], []);
      expect(out.length).assertEqual(0);
    });
  });
}
