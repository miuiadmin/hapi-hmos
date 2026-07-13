// Skills 纯逻辑单测 —— $ 技能联想评分（对照 web useSkills.getSuggestions + recent-skills.ts）
//
// 覆盖：空查询（recency 降序 + name 升序）、精确/前缀/包含/Levenshtein 评分、
//       排序（score 升序 → recency 降序 → name 升序）、recency key 为原样名（区分大小写）、无匹配→空。

import { describe, it, expect } from '@ohos/hypium';
import { skillSuggestions } from '../main/ets/chat/Skills';
import { SkillItem } from '../main/ets/models/Types';

function skill(name: string, desc: string = ''): SkillItem {
  const s = new SkillItem();
  s.name = name;
  s.description = desc;
  return s;
}

function namesOf(list: SkillItem[]): string[] {
  return list.map((s: SkillItem): string => s.name);
}

export default function skillsTest(): void {
  describe('skillSuggestions — 空查询', () => {
    it('无 recency → name 升序（代码点）', 0, () => {
      const skills = [skill('zebra'), skill('apple'), skill('mango')];
      const recent = new Map<string, number>();
      const r = skillSuggestions(skills, '', recent);
      expect(namesOf(r)).assertEqual(['apple', 'mango', 'zebra']);
    });
    it('$ 前缀视作空 → 全部', 0, () => {
      const skills = [skill('b'), skill('a')];
      const r = skillSuggestions(skills, '$', new Map<string, number>());
      expect(namesOf(r)).assertEqual(['a', 'b']);
    });
    it('有 recency → recency 降序，tiebreak name 升序', 0, () => {
      const skills = [skill('a'), skill('b'), skill('c')];
      const recent = new Map<string, number>();
      recent.set('b', 100);
      recent.set('a', 50);
      const r = skillSuggestions(skills, '', recent);
      expect(namesOf(r)).assertEqual(['b', 'a', 'c']);   // b(100) a(50) c(0)
    });
  });

  describe('skillSuggestions — 评分与匹配', () => {
    it('精确(0) 优先于 前缀(1)：$git → git, github', 0, () => {
      const skills = [skill('github'), skill('git')];
      const r = skillSuggestions(skills, '$git', new Map<string, number>());
      expect(namesOf(r)).assertEqual(['git', 'github']);
    });
    it('前缀(1)：$gi → git, github（name 升序）', 0, () => {
      const skills = [skill('github'), skill('git')];
      const r = skillSuggestions(skills, '$gi', new Map<string, number>());
      expect(namesOf(r)).assertEqual(['git', 'github']);
    });
    it('包含(2)：$it → 命中含 "it" 的名（kite 含 it；abc 编辑距超限排除）', 0, () => {
      const skills = [skill('git'), skill('kite'), skill('abc')];
      const r = skillSuggestions(skills, '$it', new Map<string, number>());
      // git/kite 均含 "it"(score2，name 升序 git<kite)；abc: it→abc dist3 > max2 → 排除
      expect(namesOf(r)).assertEqual(['git', 'kite']);
    });
    it('Levenshtein≤max：$gut → git(dist1)；dog(dist3) 排除', 0, () => {
      // searchTerm "gut" len3 → max(2, floor(3/2)=1)=2；gut→git dist1 ≤2 命中(score4)；
      //   gut→dog dist3 >2 排除（prefix/includes 均不命中）
      const skills = [skill('git'), skill('dog')];
      const r = skillSuggestions(skills, '$gut', new Map<string, number>());
      expect(namesOf(r)).assertEqual(['git']);
    });
    it('无匹配 → 空（$zzz）', 0, () => {
      const skills = [skill('git'), skill('cat')];
      // "zzz" len3 max=2；zzz→git dist=3, zzz→cat dist=3 均>2 → 空
      expect(skillSuggestions(skills, '$zzz', new Map<string, number>()).length).assertEqual(0);
    });
  });

  describe('skillSuggestions — 排序与 recency key', () => {
    it('同 score：recency 降序优先', 0, () => {
      // car/cat 均前缀 "ca"(score1)；recent 给 car → car 在前
      const skills = [skill('cat'), skill('car')];
      const recent = new Map<string, number>();
      recent.set('car', 100);
      const r = skillSuggestions(skills, '$ca', recent);
      expect(namesOf(r)).assertEqual(['car', 'cat']);
    });
    it('同 score 同 recency：name 升序', 0, () => {
      const skills = [skill('cat'), skill('car')];
      const r = skillSuggestions(skills, '$ca', new Map<string, number>());
      expect(namesOf(r)).assertEqual(['car', 'cat']);
    });
    it('recency key 区分大小写（原样名）：大写名查小写 key 命不中', 0, () => {
      // 技能名 "Git"（大写 G）；recent 存 "git"（小写）→ getRecency("Git")=0
      const skills = [skill('git'), skill('Git')];
      const recent = new Map<string, number>();
      recent.set('git', 100);
      // 空查询：git(100) 在前，Git(0) 在后
      const r = skillSuggestions(skills, '', recent);
      expect(namesOf(r)).assertEqual(['git', 'Git']);
    });
  });
}
