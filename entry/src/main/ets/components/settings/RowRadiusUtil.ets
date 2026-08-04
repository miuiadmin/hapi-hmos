// 行连续圆角工具（对照 berry3 components/utils/RowRadiusUtil.ets）。
// SettingCard 按压灰底调 resolveRowRadius(rowPosition) 咬合 ListItemGroup 外卡 r20 轮廓：
//   首行上圆下直 / 末行上直下圆 / 中间全直 / 单行全圆。
// ⚠️ 须配合 ListItemGroup .clip(true) + padding 清零，否则灰底圆心与外卡圆心错位 → 露缝。

export type RowPosition = 'single' | 'first' | 'middle' | 'last';

// 按 pos 解析四角圆角（radius 默认 20 = setting_card_radius，与外卡 ListItemGroup 圆心重合）
export function resolveRowRadius(pos: RowPosition, radius: number = 20): BorderRadiuses {
  let r: BorderRadiuses;
  switch (pos) {
    case 'first':
      r = { topLeft: radius, topRight: radius, bottomLeft: 0, bottomRight: 0 };
      break;
    case 'middle':
      r = { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 };
      break;
    case 'last':
      r = { topLeft: 0, topRight: 0, bottomLeft: radius, bottomRight: radius };
      break;
    default: // single
      r = { topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius };
      break;
  }
  return r;
}

// 按行序算 pos（页面 ForEach 内调）：单行 single / 首行 first / 末行 last / 其余 middle
export function rowPos(index: number, total: number): RowPosition {
  if (total <= 1) {
    return 'single';
  }
  if (index === 0) {
    return 'first';
  }
  if (index === total - 1) {
    return 'last';
  }
  return 'middle';
}
