// 莫兰迪图标方块色（设置首页入口列表 iOS 风彩色图标用）。
// 对照 berry3 resources/base|dark/element/color.json 的 morandi_* token（13 色 light/dark 双套）。
// ⚠️ hapi-hmos 颜色统一走 JS 调色板（paletteOf(isDark) 驱动，不走系统 colorMode 自动解析），
//   故莫兰迪色也在 JS 侧定义（不像 berry3 用 $r 资源 + base/dark 双份），与 Palette.ets 架构一致。

// 13 色键（字面量联合，ALL_ITEMS 数据驱动用；morandiSwatch switch 消化，避免动态索引访问）
export type MorandiKey =
  | 'gray' | 'purple' | 'blue' | 'green' | 'orange'
  | 'cyan' | 'brown' | 'yellow' | 'pink' | 'blueDeep'
  | 'purpleBlue' | 'grayDeep' | 'teal';

export interface MorandiColors {
  gray: string;
  purple: string;
  blue: string;
  green: string;
  orange: string;
  cyan: string;
  brown: string;
  yellow: string;
  pink: string;
  blueDeep: string;
  purpleBlue: string;
  grayDeep: string;
  teal: string;
}

// 浅色（照搬 berry3 base/element/color.json morandi_*）
export const MORANDI_LIGHT: MorandiColors = {
  gray: '#8E8A93',
  purple: '#9B8FA8',
  blue: '#7E9DB8',
  green: '#7BA088',
  orange: '#B58A72',
  cyan: '#6FA09B',
  brown: '#9C8E7E',
  yellow: '#B8A66E',
  pink: '#B88989',
  blueDeep: '#6B89A3',
  purpleBlue: '#8A85A8',
  grayDeep: '#7A767E',
  teal: '#7E9BA0'
};

// 深色（照搬 berry3 dark/element/color.json morandi_*，普遍压暗 ~30%）
export const MORANDI_DARK: MorandiColors = {
  gray: '#5A565E',
  purple: '#5E546B',
  blue: '#4A6580',
  green: '#466150',
  orange: '#6E5448',
  cyan: '#446660',
  brown: '#625A50',
  yellow: '#706544',
  pink: '#6E5454',
  blueDeep: '#42556B',
  purpleBlue: '#56536B',
  grayDeep: '#4E4A52',
  teal: '#4A6065'
};

// 按明暗取莫兰迪色板
export function morandiOf(isDark: boolean): MorandiColors {
  return isDark ? MORANDI_DARK : MORANDI_LIGHT;
}

// 按键取当前明暗下的单色（switch 消化联合 key，规避 ArkTS 严格模式动态索引访问）
export function morandiSwatch(key: MorandiKey, isDark: boolean): string {
  const m: MorandiColors = morandiOf(isDark);
  switch (key) {
    case 'gray': return m.gray;
    case 'purple': return m.purple;
    case 'blue': return m.blue;
    case 'green': return m.green;
    case 'orange': return m.orange;
    case 'cyan': return m.cyan;
    case 'brown': return m.brown;
    case 'yellow': return m.yellow;
    case 'pink': return m.pink;
    case 'blueDeep': return m.blueDeep;
    case 'purpleBlue': return m.purpleBlue;
    case 'grayDeep': return m.grayDeep;
    case 'teal': return m.teal;
    default: return m.gray;
  }
}
