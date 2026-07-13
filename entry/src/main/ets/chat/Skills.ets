// $ 技能联想（对照 web useSkills.getSuggestions + lib/recent-skills.ts）
//   纯逻辑评分 + 最近使用持久化。数据源 GET /api/sessions/:id/skills（SkillItem{name,description}）。
//
// 评分（逐字移植 useSkills.getSuggestions）：query 剥 '$' 小写；
//   空 → 全部按 recency 降序 + name 升序；否则 精确=0 / 前缀=1 / 包含=2 / Levenshtein≤max(2,len/2)=3+dist，
//   过滤未命中，按 score 升序、recency 降序、name 升序排序。
//   recency key 是技能【原样名】（上游 recent[name] 同款），非小写。
//   Levenshtein 复用 SlashCommands.levenshteinDistance（同算法，避免重复）。
//
// 持久化（对照 recent-skills.ts）：PreferencesService key hapi_recent_skills，JSON map name→timestamp，
//   上限 200（按 timestamp 降序截断）。ArkTS getString/putString 均 async，故 load/mark 为 Promise。

import { SkillItem } from '../models/Types';
import { KvStore } from '../services/KvStore';
import { PreferenceKeys } from '../config/Keys';
import { levenshteinDistance } from './SlashCommands';

const MAX_RECENT_SKILLS: number = 200;

// 字符串升序比较（代码点）。ArkTS 不稳支持 localeCompare，用 </> 替代上游 localeCompare 的 tiebreak。
function compareStrings(a: string, b: string): number {
  if (a < b) { return -1; }
  if (a > b) { return 1; }
  return 0;
}

// 技能建议（对照 useSkills.getSuggestions）。recent 的 key 是技能原样名（非小写）。
export function skillSuggestions(skills: SkillItem[], query: string, recent: Map<string, number>): SkillItem[] {
  const searchTerm: string = query.startsWith('$') ? query.substring(1).toLowerCase() : query.toLowerCase();
  const getRecency = (name: string): number => {
    const v = recent.get(name);
    return v !== undefined ? v : 0;
  };

  // 空查询：全部按 recency 降序，tiebreak name 升序
  if (searchTerm === '') {
    const order: number[] = [];
    for (let i = 0; i < skills.length; i++) { order.push(i); }
    order.sort((a: number, b: number): number => {
      const ra = getRecency(skills[a].name);
      const rb = getRecency(skills[b].name);
      if (rb !== ra) { return rb - ra; }
      return compareStrings(skills[a].name, skills[b].name);
    });
    const out: SkillItem[] = [];
    for (let i = 0; i < order.length; i++) { out.push(skills[order[i]]); }
    return out;
  }

  const maxDistance: number = Math.max(2, Math.floor(searchTerm.length / 2));
  const matched: SkillItem[] = [];
  const scores: number[] = [];
  const recencies: number[] = [];
  for (let i = 0; i < skills.length; i++) {
    const name: string = skills[i].name.toLowerCase();
    let score: number = -1;   // -1 = 不入选（替代上游 Infinity）
    if (name === searchTerm) {
      score = 0;
    } else if (name.startsWith(searchTerm)) {
      score = 1;
    } else if (name.indexOf(searchTerm) >= 0) {
      score = 2;
    } else {
      const dist: number = levenshteinDistance(searchTerm, name);
      score = dist <= maxDistance ? 3 + dist : -1;
    }
    if (score >= 0) {
      matched.push(skills[i]);
      scores.push(score);
      recencies.push(getRecency(skills[i].name));
    }
  }
  // score 升序 → recency 降序 → name 升序（下标排序，避免对象数组比较器）
  const order: number[] = [];
  for (let i = 0; i < matched.length; i++) { order.push(i); }
  order.sort((a: number, b: number): number => {
    if (scores[a] !== scores[b]) { return scores[a] - scores[b]; }
    if (recencies[b] !== recencies[a]) { return recencies[b] - recencies[a]; }
    return compareStrings(matched[a].name, matched[b].name);
  });
  const out: SkillItem[] = [];
  for (let i = 0; i < order.length; i++) { out.push(matched[order[i]]); }
  return out;
}

// 读最近使用技能 map（name→timestamp）。JSON 损坏/空 → 空 map（对照 getRecentSkills 容错）。
export async function loadRecentSkills(store: KvStore): Promise<Map<string, number>> {
  const raw: string = await store.getString(PreferenceKeys.RECENT_SKILLS, '');
  return parseRecentSkills(raw);
}

// 标记技能已使用：name=Date.now()，按 timestamp 降序截断 200，持久化（对照 markSkillUsed）。
//   空名静默跳过；持久化失败由调用方 catch（不阻塞选中回填）。
export async function markSkillUsed(skillName: string, store: KvStore): Promise<void> {
  const name: string = skillName.trim();
  if (name === '') { return; }
  const map: Map<string, number> = await loadRecentSkills(store);
  const raw: string = mergeRecentSkill(map, name, Date.now());
  await store.putString(PreferenceKeys.RECENT_SKILLS, raw);
}

// 纯：raw JSON 串 → recent map。空/损坏 → 空 map；跳过空 key 与非 number 值（对照 loadRecentSkills 容错）。
export function parseRecentSkills(raw: string): Map<string, number> {
  const map: Map<string, number> = new Map();
  if (raw === '') { return map; }
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(raw) as Record<string, Object>;
  } catch (e) {
    return map;
  }
  const keys: string[] = Object.keys(parsed);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k.trim().length === 0) { continue; }
    const v = parsed[k];
    if (typeof v === 'number') { map.set(k, v); }
  }
  return map;
}

// 纯：recent map + 本次使用(name, ts) → 截断 MAX_RECENT_SKILLS(200) 的 JSON 串。
//   不修改入参 map（拷贝后 set）；空 name → 仅序列化原 map（无新增）。
export function mergeRecentSkill(map: Map<string, number>, name: string, ts: number): string {
  const merged: Map<string, number> = new Map<string, number>();
  map.forEach((v: number, k: string) => { merged.set(k, v); });
  if (name.trim() !== '') { merged.set(name, ts); }
  const names: string[] = [];
  const tss: number[] = [];
  merged.forEach((v: number, k: string) => { names.push(k); tss.push(v); });
  const order: number[] = [];
  for (let i = 0; i < names.length; i++) { order.push(i); }
  order.sort((a: number, b: number): number => tss[b] - tss[a]);
  const obj: Record<string, number> = {};
  const limit: number = Math.min(order.length, MAX_RECENT_SKILLS);
  for (let i = 0; i < limit; i++) {
    obj[names[order[i]]] = tss[order[i]];
  }
  return JSON.stringify(obj);
}
