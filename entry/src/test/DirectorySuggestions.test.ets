// DirectorySuggestions 单测 —— 目录建议纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照上游 useDirectorySuggestions.ts 语义：machineId 过滤 + path/worktree 两源 + recent 在前 + 余 localeCompare。
//   覆盖 path/worktree 合并去重 / recent 优先 / machineId 过滤 / 空 recent / metadata=null。

import { describe, it, expect } from '@ohos/hypium';
import { SessionSummary, SessionSummaryMetadata } from '../main/ets/models/Types';
import { buildDirectorySuggestions } from '../main/ets/chat/DirectorySuggestions';

// 测试夹具：造一个带 metadata 的 SessionSummary（path + machineId + worktreeBasePath 可选）
function mkSession(id: string, machineId: string, path: string, worktreeBase: string): SessionSummary {
  const s: SessionSummary = new SessionSummary();
  s.id = id;
  const m: SessionSummaryMetadata = new SessionSummaryMetadata();
  m.machineId = machineId;
  m.path = path;
  m.worktreeBasePath = worktreeBase;
  s.metadata = m;
  return s;
}

// 测试夹具：metadata=null 的会话（应被两源收集跳过）
function mkNullSession(id: string): SessionSummary {
  const s: SessionSummary = new SessionSummary();
  s.id = id;
  s.metadata = null;
  return s;
}

export default function directorySuggestionsTest(): void {
  describe('DirectorySuggestions — recent 在前 + 余 localeCompare 升序', () => {
    it('recent 保留在结果前段（顺序不变）', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/home/a/proj', ''),
        mkSession('s2', 'm1', '/home/z/other', '')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, ['/home/recent1', '/home/recent2']);
      expect(out[0]).assertEqual('/home/recent1');
      expect(out[1]).assertEqual('/home/recent2');
    });
    it('非 recent 的 session path 按 localeCompare 升序排在 recent 之后', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/zzz', ''),
        mkSession('s2', 'm1', '/aaa', '')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, ['/recent']);
      // recent 在前，余按字典序：/aaa < /zzz
      expect(out[0]).assertEqual('/recent');
      expect(out[1]).assertEqual('/aaa');
      expect(out[2]).assertEqual('/zzz');
    });
  });

  describe('DirectorySuggestions — path + worktree 两源合并去重', () => {
    it('同 path 出现在多会话仅一次', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/dup', ''),
        mkSession('s2', 'm1', '/dup', '')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/dup');
    });
    it('worktree.basePath 作为第二源并入', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/main', '/wt/base')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(2);
      // 字典序：/main < /wt/base
      expect(out[0]).assertEqual('/main');
      expect(out[1]).assertEqual('/wt/base');
    });
    it('path 与 worktree 同值去重', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/same', '/same')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/same');
    });
  });

  describe('DirectorySuggestions — recent 去重并排除已在 recent 的 session path', () => {
    it('recent 内重复项去重（保序）', 0, () => {
      const out: string[] = buildDirectorySuggestions('m1', [], ['/r', '/r', '/r2']);
      expect(out.length).assertEqual(2);
      expect(out[0]).assertEqual('/r');
      expect(out[1]).assertEqual('/r2');
    });
    it('session path 已在 recent → 不重复出现在余段', 0, () => {
      const sessions: SessionSummary[] = [mkSession('s1', 'm1', '/also-recent', '')];
      const out: string[] = buildDirectorySuggestions('m1', sessions, ['/also-recent']);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/also-recent');
    });
  });

  describe('DirectorySuggestions — machineId 过滤', () => {
    it('machineId 非空：仅取该机会话的 path', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/m1-path', ''),
        mkSession('s2', 'm2', '/m2-path', '')
      ];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/m1-path');
    });
    it('machineId=null：取全部会话（不过滤）', 0, () => {
      const sessions: SessionSummary[] = [
        mkSession('s1', 'm1', '/a', ''),
        mkSession('s2', 'm2', '/b', '')
      ];
      const out: string[] = buildDirectorySuggestions(null, sessions, []);
      expect(out.length).assertEqual(2);
      expect(out[0]).assertEqual('/a');
      expect(out[1]).assertEqual('/b');
    });
    it('metadata.machineId 空串：非空 machineId 过滤时不命中', 0, () => {
      const sessions: SessionSummary[] = [mkSession('s1', '', '/no-machine', '')];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(0);
    });
  });

  describe('DirectorySuggestions — 边界', () => {
    it('空 recent + 有会话 → 仅 session 源', 0, () => {
      const sessions: SessionSummary[] = [mkSession('s1', 'm1', '/x', '')];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/x');
    });
    it('metadata=null 会话：两源均跳过（无 path/worktree）', 0, () => {
      const sessions: SessionSummary[] = [mkNullSession('s1')];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(0);
    });
    it('path 空串：跳过（不进结果）', 0, () => {
      const sessions: SessionSummary[] = [mkSession('s1', 'm1', '', '/wt-only')];
      const out: string[] = buildDirectorySuggestions('m1', sessions, []);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('/wt-only');
    });
    it('全空 → 空数组', 0, () => {
      expect(buildDirectorySuggestions('m1', [], []).length).assertEqual(0);
    });
  });
}
