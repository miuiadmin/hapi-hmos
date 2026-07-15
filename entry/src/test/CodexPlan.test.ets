// CodexPlan 纯逻辑单测 —— 对照 web/src/chat/normalizeAgent.ts:110-148。
//   覆盖 normalizePlanStatus（trim/小写/空白-连字符→下划线 + 三类归一）与 normalizePlanEntries
//   （数组 / {plan|items|steps} 解析、step/content/text/title/description 回落、status??state 归一、
//   空 step 跳过）。输入用 JSON.parse 构造任意结构（normalizePlanEntries 取 Object）。

import { describe, it, expect } from '@ohos/hypium';
import { normalizePlanStatus, normalizePlanEntries, PlanEntry } from '../main/ets/chat/CodexPlan';

export default function codexPlanTest(): void {

  describe('normalizePlanStatus — 三类归一', () => {
    it('completed/complete/done → completed（含大小写）', 0, () => {
      expect(normalizePlanStatus('completed')).assertEqual('completed');
      expect(normalizePlanStatus('complete')).assertEqual('completed');
      expect(normalizePlanStatus('done')).assertEqual('completed');
      expect(normalizePlanStatus('Done')).assertEqual('completed');
      expect(normalizePlanStatus('DONE')).assertEqual('completed');
    });
    it('in_progress/inprogress/active/running → in_progress', 0, () => {
      expect(normalizePlanStatus('in_progress')).assertEqual('in_progress');
      expect(normalizePlanStatus('inprogress')).assertEqual('in_progress');
      expect(normalizePlanStatus('active')).assertEqual('in_progress');
      expect(normalizePlanStatus('running')).assertEqual('in_progress');
    });
    it('空白/连字符归一：In Progress / in-progress → in_progress', 0, () => {
      expect(normalizePlanStatus('In Progress')).assertEqual('in_progress');
      expect(normalizePlanStatus('in-progress')).assertEqual('in_progress');
    });
    it('trim 首尾空白：  done  → completed', 0, () => {
      expect(normalizePlanStatus('  done  ')).assertEqual('completed');
    });
    it('pending/空/未知 → pending', 0, () => {
      expect(normalizePlanStatus('pending')).assertEqual('pending');
      expect(normalizePlanStatus('')).assertEqual('pending');
      expect(normalizePlanStatus('foobar')).assertEqual('pending');
    });
    it('非字符串 → pending', 0, () => {
      expect(normalizePlanStatus(42 as Object)).assertEqual('pending');
      expect(normalizePlanStatus(null as Object)).assertEqual('pending');
    });
  });

  describe('normalizePlanEntries — 字符串数组', () => {
    it('字符串数组 → 全 pending', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(JSON.parse('["a","b"]') as Object);
      expect(plan.length).assertEqual(2);
      expect(plan[0].step).assertEqual('a');
      expect(plan[0].status).assertEqual('pending');
      expect(plan[1].step).assertEqual('b');
      expect(plan[1].status).assertEqual('pending');
    });
    it('数组中空字符串跳过', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(JSON.parse('["","a"]') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('a');
    });
  });

  describe('normalizePlanEntries — 对象源（plan/items/steps）', () => {
    it('{plan:[{step,status},{step}]} 解析 + status 归一', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"plan":[{"step":"x","status":"completed"},{"step":"y"}]}') as Object);
      expect(plan.length).assertEqual(2);
      expect(plan[0].step).assertEqual('x');
      expect(plan[0].status).assertEqual('completed');
      expect(plan[1].step).assertEqual('y');
      expect(plan[1].status).assertEqual('pending');
    });
    it('{items:[{content,state}]} 用 content 键 + state 归一', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"items":[{"content":"c","state":"running"}]}') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('c');
      expect(plan[0].status).assertEqual('in_progress');
    });
    it('{steps:[{title}]} 用 title 键', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"steps":[{"title":"t"}]}') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('t');
      expect(plan[0].status).assertEqual('pending');
    });
    it('description 回落：{plan:[{description:"d"}]} → step=d', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"plan":[{"description":"d"}]}') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('d');
    });
    it('plan 优先于 items/steps', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"plan":[{"step":"p"}],"items":[{"step":"i"}]}') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('p');
    });
  });

  describe('normalizePlanEntries — 边界', () => {
    it('空 step 跳过', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('{"plan":[{"step":""},{"step":"ok"}]}') as Object);
      expect(plan.length).assertEqual(1);
      expect(plan[0].step).assertEqual('ok');
    });
    it('无 plan/items/steps 的对象 → []', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(JSON.parse('{"foo":"bar"}') as Object);
      expect(plan.length).assertEqual(0);
    });
    it('空数组 → []', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(JSON.parse('[]') as Object);
      expect(plan.length).assertEqual(0);
    });
    it('null/非对象非数组 → []', 0, () => {
      expect(normalizePlanEntries(null as Object).length).assertEqual(0);
      expect(normalizePlanEntries('str' as Object).length).assertEqual(0);
    });
    it('混合数组：字符串 + 对象（text 键 + done）', 0, () => {
      const plan: PlanEntry[] = normalizePlanEntries(
        JSON.parse('["s",{"text":"t","status":"done"}]') as Object);
      expect(plan.length).assertEqual(2);
      expect(plan[0].step).assertEqual('s');
      expect(plan[0].status).assertEqual('pending');
      expect(plan[1].step).assertEqual('t');
      expect(plan[1].status).assertEqual('completed');
    });
  });
}
