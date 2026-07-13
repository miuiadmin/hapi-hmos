// TerminalInput 纯逻辑单测 —— 触屏快捷键 / 修饰键合成 / UUID（对照 web routes/sessions/terminal.tsx）
//
// 覆盖：QUICK_INPUT_ROWS 结构与合法性；applyModifierState（ctrl 控制字符 / alt ESC 前缀 / 组合 / 多字符不作用）；
//       shouldResetModifiers（空序列不复位 / 有修饰键则复位）；uuid 格式（长度/分隔/版本位/变体位）+ 唯一性。

import { describe, it, expect } from '@ohos/hypium';
import {
  QUICK_INPUT_ROWS,
  applyModifierState,
  shouldResetModifiers,
  uuid,
  classifyTerminalError,
  ModifierState
} from '../main/ets/chat/TerminalInput';

function st(ctrl: boolean, alt: boolean): ModifierState {
  return { ctrl: ctrl, alt: alt };
}

export default function terminalInputTest(): void {
  describe('QUICK_INPUT_ROWS — 结构', () => {
    it('3 行且每行非空', 0, () => {
      expect(QUICK_INPUT_ROWS.length).assertEqual(3);
      for (let i = 0; i < QUICK_INPUT_ROWS.length; i++) {
        expect(QUICK_INPUT_ROWS[i].length > 0).assertEqual(true);
      }
    });
    it('每项 label 非空', 0, () => {
      for (let i = 0; i < QUICK_INPUT_ROWS.length; i++) {
        const row = QUICK_INPUT_ROWS[i];
        for (let j = 0; j < row.length; j++) {
          expect(row[j].label.length > 0).assertEqual(true);
        }
      }
    });
    it('seq 键 seq 非空；ctrl/alt 切换键 seq 为空', 0, () => {
      for (let i = 0; i < QUICK_INPUT_ROWS.length; i++) {
        const row = QUICK_INPUT_ROWS[i];
        for (let j = 0; j < row.length; j++) {
          const k = row[j];
          if (k.kind === 'seq') {
            expect(k.seq.length > 0).assertEqual(true);
          } else {
            expect(k.seq === '').assertEqual(true);   // ctrl/alt 切换键
          }
        }
      }
    });
    it('每行恰好含一个 Ctrl + 一个 Alt 切换键（前两行）', 0, () => {
      // 第 2 行（index 1）含 Ctrl/Alt；其余行纯 seq
      let ctrlAltSeen = false;
      for (let i = 0; i < QUICK_INPUT_ROWS.length; i++) {
        const row = QUICK_INPUT_ROWS[i];
        let hasCtrl = false;
        let hasAlt = false;
        for (let j = 0; j < row.length; j++) {
          if (row[j].kind === 'ctrl') { hasCtrl = true; }
          if (row[j].kind === 'alt') { hasAlt = true; }
        }
        if (hasCtrl || hasAlt) {
          ctrlAltSeen = true;
          expect(hasCtrl && hasAlt).assertEqual(true);   // 同行同时有
          expect(i === 1).assertEqual(true);             // 只在第 2 行
        }
      }
      expect(ctrlAltSeen).assertEqual(true);
    });
  });

  describe('applyModifierState — ctrl 控制字符', () => {
    it("ctrl+'c' → ETX(\\x03)", 0, () => {
      expect(applyModifierState('c', st(true, false))).assertEqual('\x03');
    });
    it("ctrl+'d' → EOT(\\x04)", 0, () => {
      expect(applyModifierState('d', st(true, false))).assertEqual('\x04');
    });
    it("ctrl+'z' → SUB(\\x1a)", 0, () => {
      expect(applyModifierState('z', st(true, false))).assertEqual('\x1a');
    });
    it("ctrl+'l' → FF(\\x0c)", 0, () => {
      expect(applyModifierState('l', st(true, false))).assertEqual('\x0c');
    });
    it("ctrl+'@' → NUL(\\x00)，边界下限 64", 0, () => {
      expect(applyModifierState('@', st(true, false))).assertEqual('\x00');
    });
    it("ctrl+'_' → US(\\x1f)，边界上限 95", 0, () => {
      expect(applyModifierState('_', st(true, false))).assertEqual('\x1f');
    });
    it("大写 'C' 与小写 'c' 同结果（toUpperCase 归一）", 0, () => {
      expect(applyModifierState('C', st(true, false))).assertEqual('\x03');
    });
  });

  describe('applyModifierState — alt 前缀 / 无修饰 / 多字符', () => {
    it("alt+'x' → ESC+x(\\x1bx)", 0, () => {
      expect(applyModifierState('x', st(false, true))).assertEqual('\x1bx');
    });
    it('无修饰 → 原样返回', 0, () => {
      expect(applyModifierState('c', st(false, false))).assertEqual('c');
      expect(applyModifierState('\x1b[A', st(false, false))).assertEqual('\x1b[A');
    });
    it('ctrl+alt+单字符 → alt 先加（长 2）→ ctrl 分支跳过 → ESC+char', 0, () => {
      // 对照上游：alt 先作用使长度变 2，ctrl 的 length===1 守卫不再满足
      expect(applyModifierState('c', st(true, true))).assertEqual('\x1bc');
    });
    it('ctrl + 多字符序列 → 不作用（length>1）', 0, () => {
      expect(applyModifierState('\x1b[A', st(true, false))).assertEqual('\x1b[A');
    });
  });

  describe('shouldResetModifiers', () => {
    it('空序列 → 不复位（即使修饰键激活）', 0, () => {
      expect(shouldResetModifiers('', st(true, false))).assertEqual(false);
    });
    it('序列非空 + ctrl 激活 → 复位', 0, () => {
      expect(shouldResetModifiers('c', st(true, false))).assertEqual(true);
    });
    it('序列非空 + alt 激活 → 复位', 0, () => {
      expect(shouldResetModifiers('x', st(false, true))).assertEqual(true);
    });
    it('序列非空 + 无修饰 → 不复位', 0, () => {
      expect(shouldResetModifiers('c', st(false, false))).assertEqual(false);
    });
  });

  describe('uuid — 格式', () => {
    it('长度 36 + 4 个连字符（8-4-4-4-12）', 0, () => {
      const id: string = uuid();
      expect(id.length).assertEqual(36);
      expect(id.charAt(8)).assertEqual('-');
      expect(id.charAt(13)).assertEqual('-');
      expect(id.charAt(18)).assertEqual('-');
      expect(id.charAt(23)).assertEqual('-');
    });
    it('版本位 char[14] === "4"', 0, () => {
      expect(uuid().charAt(14)).assertEqual('4');
    });
    it('变体位 char[19] ∈ {8,9,a,b}', 0, () => {
      const c: string = uuid().charAt(19);
      expect(c === '8' || c === '9' || c === 'a' || c === 'b').assertEqual(true);
    });
    it('所有非连字符位均为十六进制', 0, () => {
      const id: string = uuid();
      const hex: string = '0123456789abcdef';
      for (let i = 0; i < id.length; i++) {
        const ch: string = id.charAt(i);
        if (ch === '-') { continue; }
        expect(hex.indexOf(ch) >= 0).assertEqual(true);
      }
    });
    it('50 次生成均唯一（概率性，正常熵下必然）', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < 50; i++) {
        const id: string = uuid();
        expect(seen.has(id)).assertEqual(false);
        seen.add(id);
      }
    });
  });

  // classifyTerminalError — terminal:error 文案分类（对照 hub/src/socket/handlers/terminal.ts 真实文案常量）。
  //   Hub 无 terminal:quota 事件：配额超限走 error 文案。本测试用 Hub 真实字符串逐条断言分类 + max 提取。
  describe('classifyTerminalError — 配额 (quota)', () => {
    it('socket 级配额文案 → quota + max 提取', 0, () => {
      const info = classifyTerminalError('Too many terminals open (max 4).');
      expect(info.kind).assertEqual('quota');
      expect(info.max).assertEqual(4);
    });
    it('session 级配额文案 → quota + max 提取', 0, () => {
      const info = classifyTerminalError('Too many terminals open for this session (max 4).');
      expect(info.kind).assertEqual('quota');
      expect(info.max).assertEqual(4);
    });
    it('不同上限数值正确提取', 0, () => {
      const info = classifyTerminalError('Too many terminals open (max 8).');
      expect(info.kind).assertEqual('quota');
      expect(info.max).assertEqual(8);
    });
    it('大小写无关（"TOO MANY TERMINALS"）', 0, () => {
      const info = classifyTerminalError('too many terminals open (max 2).');
      expect(info.kind).assertEqual('quota');
      expect(info.max).assertEqual(2);
    });
    it('配额文案缺 (max N) → quota 但 max=-1', 0, () => {
      // 防御：文案改版丢数字时仍归 quota，max 留 -1（UI 回落通用配额文案）
      const info = classifyTerminalError('Too many terminals open.');
      expect(info.kind).assertEqual('quota');
      expect(info.max).assertEqual(-1);
    });
  });

  describe('classifyTerminalError — 非配额分类', () => {
    it('"Session is inactive or unavailable." → inactive', 0, () => {
      expect(classifyTerminalError('Session is inactive or unavailable.').kind).assertEqual('inactive');
    });
    it('"CLI is not connected for this session." → cli', 0, () => {
      expect(classifyTerminalError('CLI is not connected for this session.').kind).assertEqual('cli');
    });
    it('"CLI disconnected." → cli', 0, () => {
      expect(classifyTerminalError('CLI disconnected.').kind).assertEqual('cli');
    });
    it('"Terminal ID is already in use." → generic', 0, () => {
      const info = classifyTerminalError('Terminal ID is already in use.');
      expect(info.kind).assertEqual('generic');
      expect(info.max).assertEqual(-1);
    });
  });

  describe('classifyTerminalError — 边界', () => {
    it('空串 → generic', 0, () => {
      expect(classifyTerminalError('').kind).assertEqual('generic');
    });
    it('未知文案 → generic', 0, () => {
      const info = classifyTerminalError('Connection error');
      expect(info.kind).assertEqual('generic');
      expect(info.max).assertEqual(-1);
    });
    it('非配额类 max 恒为 -1', 0, () => {
      expect(classifyTerminalError('Session is inactive or unavailable.').max).assertEqual(-1);
      expect(classifyTerminalError('CLI disconnected.').max).assertEqual(-1);
      expect(classifyTerminalError('Terminal ID is already in use.').max).assertEqual(-1);
    });
  });
}
