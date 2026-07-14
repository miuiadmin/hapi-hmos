// SpawnError 单测 —— spawn 错误诊断纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalFontSize.test 范式：同步断言。
//   覆盖 formatMachineSpawnError：message 空 / at<=0 / at>0 组合。
//   at>0 的期望值用同源 formatDateDivider+formatClock 组合（验拼接结构：括号 + 空格），不钉本地化文案。

import { describe, it, expect } from '@ohos/hypium';
import { formatMachineSpawnError } from '../main/ets/chat/SpawnError';
import { formatDateDivider, formatClock } from '../main/ets/utils/DateFormatUtils';

export default function spawnErrorTest(): void {
  describe('SpawnError — formatMachineSpawnError message 空 → 空', () => {
    it("'' + at=0 → ''", 0, () => {
      expect(formatMachineSpawnError('', 0)).assertEqual('');
    });
    it("'' + at>0 → ''（有时间也无错误不显示）", 0, () => {
      expect(formatMachineSpawnError('', 1700000000000)).assertEqual('');
    });
  });

  describe('SpawnError — formatMachineSpawnError at<=0 → 仅 message（无时间）', () => {
    it('at=0 → message 原样', 0, () => {
      expect(formatMachineSpawnError('boom', 0)).assertEqual('boom');
    });
    it('at<0 → message 原样（负数视为无值）', 0, () => {
      expect(formatMachineSpawnError('boom', -5)).assertEqual('boom');
    });
  });

  describe('SpawnError — formatMachineSpawnError at>0 → message (日期 时分)', () => {
    const ts: number = 1700000000000;   // 固定时间戳，避免依赖当前时间
    const expected: string = `boom (${formatDateDivider(ts)} ${formatClock(ts)})`;
    it('at>0 → "message (date clock)" 组合结构', 0, () => {
      const got: string = formatMachineSpawnError('boom', ts);
      // 结构断言：以 message + " (" 开头、以 ")" 结尾、比 message 长
      expect(got.startsWith('boom (')).assertTrue();
      expect(got.endsWith(')')).assertTrue();
      expect(got.length > 'boom'.length).assertTrue();
      // 精确组合（同源函数）验拼接顺序与分隔
      expect(got).assertEqual(expected);
    });
    it('at>0 含空格的 message → 仍正确组合', 0, () => {
      const msg: string = 'agent exited with code 1';
      const got: string = formatMachineSpawnError(msg, ts);
      expect(got.startsWith(msg + ' (')).assertTrue();
      expect(got).assertEqual(`${msg} (${formatDateDivider(ts)} ${formatClock(ts)})`);
    });
  });
}
