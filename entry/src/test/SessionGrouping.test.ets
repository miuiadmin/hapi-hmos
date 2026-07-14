// SessionGrouping 单测 —— 会话列表「机器→目录」三级分组纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 GeneratedImageCacheUtils.test / SessionAttention.test 范式：同步断言（assertEqual / ===）。
//   覆盖 getGroupDisplayName / sessionDirectory / sessionMachineId / shortMachineLabel /
//   sortSessionsWithinGroup（不污染入参）/ groupSessionsByDirectory（多机器多目录分桶 + Other + unknown）/
//   isGroupCollapsed / flattenGroups（折叠/展开/搜索），对照上游 SessionList.tsx 语义。

import { describe, it, expect } from '@ohos/hypium';
import { SessionSummary, SessionSummaryMetadata } from '../main/ets/models/Types';
import {
  UNKNOWN_MACHINE_ID,
  OTHER_DIRECTORY,
  DirectoryGroup,
  MachineGroup,
  RenderRow,
  sessionDirectory,
  sessionMachineId,
  getGroupDisplayName,
  shortMachineLabel,
  sortSessionsWithinGroup,
  directoryGroupHasActive,
  machineGroupHasActive,
  sortDirectoryGroups,
  sortMachineGroups,
  groupSessionsByDirectory,
  directoryGroupKey,
  isGroupCollapsed,
  flattenGroups
} from '../main/ets/chat/SessionGrouping';

// 构造测试会话：id + machineId + path + active + updatedAt + pending。
function mk(id: string, machineId: string, path: string, active: boolean, updatedAt: number, pending: number = 0): SessionSummary {
  const s: SessionSummary = new SessionSummary();
  s.id = id;
  s.active = active;
  s.updatedAt = updatedAt;
  s.pendingRequestsCount = pending;
  const m: SessionSummaryMetadata = new SessionSummaryMetadata();
  m.machineId = machineId;
  m.path = path;
  s.metadata = m;
  return s;
}

// 取 machineId 的机器组（找不到 → null）
function findMachine(mgs: MachineGroup[], mid: string): MachineGroup | null {
  for (let i = 0; i < mgs.length; i++) {
    if (mgs[i].machineId === mid) { return mgs[i]; }
  }
  return null;
}

export default function sessionGroupingTest(): void {
  describe('SessionGrouping — getGroupDisplayName（末两段）', () => {
    it("'/a/b/c' → 'b/c'", 0, () => {
      expect(getGroupDisplayName('/a/b/c')).assertEqual('b/c');
    });
    it("'/a/b' → 'a/b'", 0, () => {
      expect(getGroupDisplayName('/a/b')).assertEqual('a/b');
    });
    it("'/a' → 'a'", 0, () => {
      expect(getGroupDisplayName('/a')).assertEqual('a');
    });
    it("'a' → 'a'（无斜杠）", 0, () => {
      expect(getGroupDisplayName('a')).assertEqual('a');
    });
    it("'/a/b/' 尾斜杠 → 'a/b'", 0, () => {
      expect(getGroupDisplayName('/a/b/')).assertEqual('a/b');
    });
    it("'///' 全斜杠 → ''", 0, () => {
      expect(getGroupDisplayName('///')).assertEqual('');
    });
    it("'' → ''", 0, () => {
      expect(getGroupDisplayName('')).assertEqual('');
    });
  });

  describe('SessionGrouping — sessionDirectory / sessionMachineId 兜底', () => {
    it('path 非空 → path', 0, () => {
      expect(sessionDirectory(mk('s', 'm1', '/work/x', false, 0))).assertEqual('/work/x');
    });
    it('path 空 → OTHER_DIRECTORY', 0, () => {
      expect(sessionDirectory(mk('s', 'm1', '', false, 0))).assertEqual(OTHER_DIRECTORY);
      expect(OTHER_DIRECTORY).assertEqual('Other');
    });
    it('metadata null → OTHER_DIRECTORY', 0, () => {
      const s: SessionSummary = new SessionSummary();
      s.id = 's';
      expect(sessionDirectory(s)).assertEqual(OTHER_DIRECTORY);
    });
    it('machineId 非空 → id', 0, () => {
      expect(sessionMachineId(mk('s', 'm1', '/p', false, 0))).assertEqual('m1');
    });
    it('machineId 空 → UNKNOWN_MACHINE_ID', 0, () => {
      expect(sessionMachineId(mk('s', '', '/p', false, 0))).assertEqual(UNKNOWN_MACHINE_ID);
      expect(UNKNOWN_MACHINE_ID).assertEqual('__unknown__');
    });
  });

  describe('SessionGrouping — shortMachineLabel', () => {
    it('长 id → 前 8 字符', 0, () => {
      expect(shortMachineLabel('abcdefghijklmnop')).assertEqual('abcdefgh');
    });
    it('短 id → 原样', 0, () => {
      expect(shortMachineLabel('m1')).assertEqual('m1');
    });
    it('UNKNOWN_MACHINE_ID → 空', 0, () => {
      expect(shortMachineLabel(UNKNOWN_MACHINE_ID)).assertEqual('');
    });
    it("'' → 空", 0, () => {
      expect(shortMachineLabel('')).assertEqual('');
    });
  });

  describe('SessionGrouping — sortSessionsWithinGroup（不污染入参）', () => {
    it('active+pending → active → inactive', 0, () => {
      const inactive: SessionSummary = mk('a', 'm', '/p', false, 100);
      const active: SessionSummary = mk('b', 'm', '/p', true, 100);
      const pending: SessionSummary = mk('c', 'm', '/p', true, 100, 3);
      const input: SessionSummary[] = [inactive, active, pending];
      const out: SessionSummary[] = sortSessionsWithinGroup(input);
      expect(out[0].id).assertEqual('c');   // pending
      expect(out[1].id).assertEqual('b');   // active
      expect(out[2].id).assertEqual('a');   // inactive
    });
    it('同 rank updatedAt 降序', 0, () => {
      const older: SessionSummary = mk('a', 'm', '/p', true, 100);
      const newer: SessionSummary = mk('b', 'm', '/p', true, 200);
      const out: SessionSummary[] = sortSessionsWithinGroup([older, newer]);
      expect(out[0].id).assertEqual('b');   // newer 在前
      expect(out[1].id).assertEqual('a');
    });
    it('入参顺序不被改写', 0, () => {
      const inactive: SessionSummary = mk('a', 'm', '/p', false, 0);
      const active: SessionSummary = mk('b', 'm', '/p', true, 0);
      const input: SessionSummary[] = [inactive, active];
      sortSessionsWithinGroup(input);
      expect(input[0].id).assertEqual('a');   // 仍是原序
      expect(input[1].id).assertEqual('b');
    });
  });

  describe('SessionGrouping — groupSessionsByDirectory（分桶 + 排序 + 兜底）', () => {
    it('两机器×两目录 → 两机器组各含其目录', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/work/a', false, 10),
        mk('s2', 'm1', '/work/b', false, 20),
        mk('s3', 'm2', '/work/a', false, 30)
      ]);
      expect(mgs.length).assertEqual(2);
      const m1: MachineGroup | null = findMachine(mgs, 'm1');
      expect(m1 !== null).assertEqual(true);
      expect((m1 as MachineGroup).groups.length).assertEqual(2);
      expect((m1 as MachineGroup).totalSessions).assertEqual(2);
      const m2: MachineGroup | null = findMachine(mgs, 'm2');
      expect((m2 as MachineGroup).groups.length).assertEqual(1);
      expect((m2 as MachineGroup).totalSessions).assertEqual(1);
    });
    it('同 path 跨机器 → 各自成组（不合并）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/work/x', false, 0),
        mk('s2', 'm2', '/work/x', false, 0)
      ]);
      expect(mgs.length).assertEqual(2);
      const m1: MachineGroup = findMachine(mgs, 'm1') as MachineGroup;
      const m2: MachineGroup = findMachine(mgs, 'm2') as MachineGroup;
      expect(m1.groups[0].directory).assertEqual('/work/x');
      expect(m2.groups[0].directory).assertEqual('/work/x');
      expect(m1.groups[0].machineId).assertEqual('m1');
      expect(m2.groups[0].machineId).assertEqual('m2');
    });
    it('空 path → OTHER_DIRECTORY 组 + displayName 空', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '', false, 0)
      ]);
      const m1: MachineGroup = findMachine(mgs, 'm1') as MachineGroup;
      expect(m1.groups[0].directory).assertEqual(OTHER_DIRECTORY);
      expect(m1.groups[0].displayName).assertEqual('');
    });
    it('空 machineId → UNKNOWN_MACHINE_ID 组', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', '', '/p', false, 0)
      ]);
      expect(mgs.length).assertEqual(1);
      expect(mgs[0].machineId).assertEqual(UNKNOWN_MACHINE_ID);
      expect(mgs[0].label).assertEqual('');   // unknown → 空 label
    });
    it('displayName = 末两段', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/a/b/c', false, 0)
      ]);
      expect(mgs[0].groups[0].displayName).assertEqual('b/c');
    });
    it('label = id 前 8 字符', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'abcdefghijklmnop', '/p', false, 0)
      ]);
      expect(mgs[0].label).assertEqual('abcdefgh');
    });
    it('有活跃的机器组排前', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'inactive', '/p', false, 999),
        mk('s2', 'active', '/p', true, 1)
      ]);
      expect(mgs[0].machineId).assertEqual('active');
    });
  });

  describe('SessionGrouping — directoryGroupKey', () => {
    it('machine::directory', 0, () => {
      const dg: DirectoryGroup = new DirectoryGroup();
      dg.machineId = 'm1';
      dg.directory = '/work/x';
      expect(directoryGroupKey(dg)).assertEqual('m1::/work/x');
    });
  });

  describe('SessionGrouping — isGroupCollapsed', () => {
    it('搜索中 → 恒展开（即使 override 折叠）', 0, () => {
      const ov: Map<string, boolean> = new Map<string, boolean>();
      ov.set('k', true);
      expect(isGroupCollapsed('k', false, true, ov)).assertEqual(false);
    });
    it('override true → 折叠', 0, () => {
      const ov: Map<string, boolean> = new Map<string, boolean>();
      ov.set('k', true);
      expect(isGroupCollapsed('k', true, false, ov)).assertEqual(true);
    });
    it('override false → 展开（即使无活跃）', 0, () => {
      const ov: Map<string, boolean> = new Map<string, boolean>();
      ov.set('k', false);
      expect(isGroupCollapsed('k', false, false, ov)).assertEqual(false);
    });
    it('无 override + 有活跃 → 展开（默认）', 0, () => {
      expect(isGroupCollapsed('k', true, false, new Map<string, boolean>())).assertEqual(false);
    });
    it('无 override + 无活跃 → 折叠（默认）', 0, () => {
      expect(isGroupCollapsed('k', false, false, new Map<string, boolean>())).assertEqual(true);
    });
  });

  describe('SessionGrouping — flattenGroups（折叠/展开/搜索）', () => {
    it('默认：无活跃机器组仅出机器头行', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', false, 0)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>());
      expect(rows.length).assertEqual(1);
      expect(rows[0].kind).assertEqual('machine');
    });
    it('override 展开机器 → 机器头 + 目录头 + 会话行', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', false, 0)
      ]);
      const ov: Map<string, boolean> = new Map<string, boolean>();
      ov.set('m1', false);   // 展开机器
      ov.set('m1::/p', false);   // 展开目录
      const rows: RenderRow[] = flattenGroups(mgs, false, ov);
      expect(rows.length).assertEqual(3);
      expect(rows[0].kind).assertEqual('machine');
      expect(rows[1].kind).assertEqual('directory');
      expect(rows[2].kind).assertEqual('session');
      expect(rows[2].session !== null).assertEqual(true);
      expect((rows[2].session as SessionSummary).id).assertEqual('s1');
    });
    it('搜索中：全展开（活跃机器组 → 全行）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 0)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, true, new Map<string, boolean>());
      expect(rows.length).assertEqual(3);   // machine + directory + session
    });
    it('行 key 带前缀（m:/d:/s:）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 0)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, true, new Map<string, boolean>());
      expect(rows[0].key).assertEqual('m:m1');
      expect(rows[1].key).assertEqual('d:m1::/p');
      expect(rows[2].key).assertEqual('s:s1');
    });
    it('展开机器但折叠目录 → 机器头 + 目录头（无会话行）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', false, 0)
      ]);
      const ov: Map<string, boolean> = new Map<string, boolean>();
      ov.set('m1', false);      // 展开机器
      ov.set('m1::/p', true);   // 折叠目录
      const rows: RenderRow[] = flattenGroups(mgs, false, ov);
      expect(rows.length).assertEqual(2);
      expect(rows[0].kind).assertEqual('machine');
      expect(rows[1].kind).assertEqual('directory');
    });
  });

  describe('SessionGrouping — flattenGroups 预览限流 + show-more（previewLimit/expandedGroups）', () => {
    it('previewLimit=0（默认）→ 不限流，全显无 show-more（后向兼容）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 3),
        mk('s2', 'm1', '/p', true, 2),
        mk('s3', 'm1', '/p', true, 1)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>());
      // machine + directory + 3 sessions（无 show-more）
      expect(rows.length).assertEqual(5);
      expect(rows[4].kind).assertEqual('session');
    });
    it('组超 previewLimit 且未展开 → 仅前 previewLimit 个会话 + show-more 行', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 3),
        mk('s2', 'm1', '/p', true, 2),
        mk('s3', 'm1', '/p', true, 1)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>(), 2, new Set<string>());
      // machine + directory + 2 sessions + 1 show-more
      expect(rows.length).assertEqual(5);
      expect(rows[2].kind).assertEqual('session');
      expect(rows[3].kind).assertEqual('session');
      expect(rows[4].kind).assertEqual('show-more');
      expect((rows[4] as RenderRow).remaining).assertEqual(1);
      expect((rows[4] as RenderRow).groupKey).assertEqual('m1::/p');
    });
    it('show-more key 带前缀 more:', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 1),
        mk('s2', 'm1', '/p', true, 0)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>(), 1, new Set<string>());
      const more: RenderRow = rows[rows.length - 1];
      expect(more.kind).assertEqual('show-more');
      expect(more.key).assertEqual('more:m1::/p');
    });
    it('组在 expandedGroups → 全显无 show-more（展开后不限流）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 3),
        mk('s2', 'm1', '/p', true, 2),
        mk('s3', 'm1', '/p', true, 1)
      ]);
      const expanded: Set<string> = new Set<string>();
      expanded.add('m1::/p');
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>(), 2, expanded);
      // machine + directory + 3 sessions（已展开 → 无 show-more）
      expect(rows.length).assertEqual(5);
      expect(rows[4].kind).assertEqual('session');
    });
    it('limit=1 边界：仅 1 会话 + show-more(remaining=2)', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 3),
        mk('s2', 'm1', '/p', true, 2),
        mk('s3', 'm1', '/p', true, 1)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>(), 1, new Set<string>());
      // machine + directory + 1 session + show-more
      expect(rows.length).assertEqual(4);
      expect(rows[2].kind).assertEqual('session');
      expect(rows[3].kind).assertEqual('show-more');
      expect((rows[3] as RenderRow).remaining).assertEqual(2);
    });
    it('搜索态不限流（isSearching=true → 即使超 previewLimit 也全显）', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 3),
        mk('s2', 'm1', '/p', true, 2),
        mk('s3', 'm1', '/p', true, 1)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, true, new Map<string, boolean>(), 1, new Set<string>());
      // 搜索态全显：machine + directory + 3 sessions（无 show-more）
      expect(rows.length).assertEqual(5);
      expect(rows[4].kind).assertEqual('session');
    });
    it('组数 == previewLimit（恰好不超）→ 全显无 show-more', 0, () => {
      const mgs: MachineGroup[] = groupSessionsByDirectory([
        mk('s1', 'm1', '/p', true, 2),
        mk('s2', 'm1', '/p', true, 1)
      ]);
      const rows: RenderRow[] = flattenGroups(mgs, false, new Map<string, boolean>(), 2, new Set<string>());
      // 恰好 == limit 不触发限流：machine + directory + 2 sessions
      expect(rows.length).assertEqual(4);
      expect(rows[3].kind).assertEqual('session');
    });
  });
}
