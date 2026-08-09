// 存储用量饼图纯层（零 @kit，LocalUnit 可测）—— 对照上游 web/src/components/settings/storageUsagePie.ts。
//   buildStorageSlices：按 database/wal/shm 字节占比算扇形起止角（-90° 起，12 点方向；末段闭合整圆）。
//   describeDonutArc：生成 SVG path 字符串（ArkUI Path.commands 原生支持 M/L/A/Z 弧命令）。
//   formatStorageBytes / formatStoragePercent：人读字节（补 GB 档）/ 百分比。
//
// ArkTS 严格：纯算术 + 显式循环（无 regex/reduce/字面量传参），对象字面量均具名 interface 标注。

export type StorageSliceKey = 'database' | 'wal' | 'shm';

export interface StorageUsageBytes {
  databaseBytes: number;
  walBytes: number;
  shmBytes: number;
}

export interface StorageSlice {
  key: StorageSliceKey;
  bytes: number;
  percent: number;
  startAngle: number;
  endAngle: number;
}

export interface PolarPoint {
  x: number;
  y: number;
}

const SLICE_ORDER: StorageSliceKey[] = ['database', 'wal', 'shm'];
const FULL_CIRCLE: number = 360;
/** 从 12 点方向起，第一段顶满（移动端首读友好）。 */
const START_ANGLE: number = -90;

function bytesForKey(usage: StorageUsageBytes, key: StorageSliceKey): number {
  if (key === 'database') { return usage.databaseBytes; }
  if (key === 'wal') { return usage.walBytes; }
  return usage.shmBytes;
}

// 按序取字节，过滤零/非有限，保序；按占比累加角度。total<=0 返回空（调用方走空态）。
export function buildStorageSlices(usage: StorageUsageBytes): StorageSlice[] {
  const keys: StorageSliceKey[] = [];
  const bytesArr: number[] = [];
  let total: number = 0;
  for (let i = 0; i < SLICE_ORDER.length; i++) {
    const key: StorageSliceKey = SLICE_ORDER[i];
    const raw: number = bytesForKey(usage, key);
    const b: number = (Number.isFinite(raw) && raw > 0) ? raw : 0;
    if (b > 0) {
      keys.push(key);
      bytesArr.push(b);
      total += b;
    }
  }
  if (total <= 0) { return []; }

  const out: StorageSlice[] = [];
  let cursor: number = START_ANGLE;
  for (let i = 0; i < keys.length; i++) {
    const isLast: boolean = i === keys.length - 1;
    const endAngle: number = isLast
      ? (START_ANGLE + FULL_CIRCLE)
      : (cursor + (bytesArr[i] / total) * FULL_CIRCLE);
    const s: StorageSlice = {
      key: keys[i],
      bytes: bytesArr[i],
      percent: Math.round((bytesArr[i] / total) * 1000) / 10,
      startAngle: cursor,
      endAngle: endAngle
    };
    out.push(s);
    cursor = endAngle;
  }
  return out;
}

export function polarToCartesian(cx: number, cy: number, radius: number, angleDeg: number): PolarPoint {
  const radians: number = (angleDeg * Math.PI) / 180;
  const p: PolarPoint = {
    x: cx + radius * Math.cos(radians),
    y: cy + radius * Math.sin(radians)
  };
  return p;
}

// 生成甜甜圈扇形 SVG path（外弧 → 内边 → 内弧反向 → 闭合）。整圆拆两段半圆避歧义。
//   ArkUI Path.commands 原生解析 M/L/A/Z；A 的参数：rx ry xrot largeArc sweep x y。
export function describeDonutArc(cx: number, cy: number, innerRadius: number, outerRadius: number,
  startAngle: number, endAngle: number): string {
  const sweep: number = endAngle - startAngle;
  if (sweep < 0.001) { return ''; }
  if (sweep >= FULL_CIRCLE - 0.001) {
    const mid: number = startAngle + 180;
    const o0: PolarPoint = polarToCartesian(cx, cy, outerRadius, startAngle);
    const o1: PolarPoint = polarToCartesian(cx, cy, outerRadius, mid);
    const o2: PolarPoint = polarToCartesian(cx, cy, outerRadius, endAngle);
    const i2: PolarPoint = polarToCartesian(cx, cy, innerRadius, endAngle);
    const i1: PolarPoint = polarToCartesian(cx, cy, innerRadius, mid);
    const i0: PolarPoint = polarToCartesian(cx, cy, innerRadius, startAngle);
    return `M ${o0.x} ${o0.y} A ${outerRadius} ${outerRadius} 0 1 1 ${o1.x} ${o1.y} `
      + `A ${outerRadius} ${outerRadius} 0 1 1 ${o2.x} ${o2.y} `
      + `L ${i2.x} ${i2.y} A ${innerRadius} ${innerRadius} 0 1 0 ${i1.x} ${i1.y} `
      + `A ${innerRadius} ${innerRadius} 0 1 0 ${i0.x} ${i0.y} Z`;
  }
  const largeArc: number = sweep > 180 ? 1 : 0;
  const o0: PolarPoint = polarToCartesian(cx, cy, outerRadius, startAngle);
  const o2: PolarPoint = polarToCartesian(cx, cy, outerRadius, endAngle);
  const i2: PolarPoint = polarToCartesian(cx, cy, innerRadius, endAngle);
  const i0: PolarPoint = polarToCartesian(cx, cy, innerRadius, startAngle);
  return `M ${o0.x} ${o0.y} A ${outerRadius} ${outerRadius} 0 ${largeArc} 1 ${o2.x} ${o2.y} `
    + `L ${i2.x} ${i2.y} A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${i0.x} ${i0.y} Z`;
}

export function formatStoragePercent(percent: number): string {
  if (!Number.isFinite(percent)) { return '0%'; }
  const rounded: number = Math.round(percent * 10) / 10;
  return Number.isInteger(rounded) ? `${rounded}%` : `${rounded.toFixed(1)}%`;
}

// 人读字节：B/KB/MB/GB（对照上游 formatFileSize，补 GB 档——SQLite 总量可能上 GB）。
export function formatStorageBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) { return '0 B'; }
  const KB: number = 1024;
  const MB: number = 1024 * 1024;
  const GB: number = 1024 * 1024 * 1024;
  if (bytes < KB) { return `${bytes} B`; }
  if (bytes < MB) { return `${(bytes / KB).toFixed(1)} KB`; }
  if (bytes < GB) { return `${(bytes / MB).toFixed(1)} MB`; }
  return `${(bytes / GB).toFixed(2)} GB`;
}
