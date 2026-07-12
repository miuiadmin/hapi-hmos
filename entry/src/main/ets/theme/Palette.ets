// 统一调色板：语义 token + 亮/暗两套 + paletteOf(isDark) + toArgb(hex)。
// 架构（详见 docs 与 memory）：JS 侧响应式主题——markdown_hybrid 的 theme setter 只吃 number，
//   且我们缓存了 markdown 配置，原生 $r 资源在 colorMode 切换时无法触发它重建；
//   故颜色统一走 JS 调色板（字符串/数字/alpha 全自然），由 ThemeState.isDark 驱动切换。
// 归一策略：把散落的近似灰合并到规范语义色（如 #888888→textSecondary、#EEEEEE→border、#E8EAED→codeBg），
//   接受少数像素微调以换取全局一致观感。

// 语义 token（全 '#RRGGBB' 实色；半透明覆盖态单独内联保留）
export interface PaletteColors {
  primary: string;          // 主色（主按钮 / 链接 / 勾选 / 引用竖条 / 头像激活 / badge 文字）
  bg: string;               // 页面 / 卡片白底
  surface: string;          // 输入框 / AI 气泡 / 工具卡底 / 次按钮底
  surfaceSelected: string;  // 选中底 / badge / pill / 代码 header 底
  textPrimary: string;      // 主要正文 / 标题
  textSecondary: string;    // 次要正文 / 副标题 / 摘要（吸收 #888888）
  textTertiary: string;     // 占位 / 提示 / 时间戳 / elapsed / idle 头像
  border: string;           // 边框 / 分割线（吸收 #EEEEEE）
  error: string;            // 错误字 / 危险按钮 / 未读角标 / diff 删除
  errorBg: string;          // 错误背景（吸收 #FFEBE9）
  success: string;          // 成功状态 / 选中勾 / diff 新增
  successBg: string;        // 成功背景 / diff 新增背景
  warning: string;          // pending / 警告（amber）
  codeText: string;         // 代码字（吸收 #333333）
  codeBg: string;           // 代码块 / 行内码 背景（吸收 #E8EAED）
  codeMuted: string;        // 代码行号 / header 字（吸收 #6E7681）
  diffAdd: string;          // diff 新增字
  diffDelete: string;       // diff 删除字
  bubbleUserText: string;   // 主色用户气泡上的字
}

// 亮色（归一后的现有值）
export const LIGHT: PaletteColors = {
  primary: '#007DFF',
  bg: '#FFFFFF',
  surface: '#F2F3F5',
  surfaceSelected: '#ECEEF1',
  textPrimary: '#1A1A1A',
  textSecondary: '#8A8A8A',
  textTertiary: '#AAAAAA',
  border: '#E5E5E5',
  error: '#E8403E',
  errorBg: '#FCEBEA',
  success: '#16A34A',
  successBg: '#E6F4EA',
  warning: '#D97706',
  codeText: '#1F2328',
  codeBg: '#F6F8FA',
  codeMuted: '#8C98A4',
  diffAdd: '#1A7F37',
  diffDelete: '#CF222E',
  bubbleUserText: '#FFFFFF'
};

// 暗色（遵循「降饱和、表面逐级抬升」惯例，DevEco 真机微调）
export const DARK: PaletteColors = {
  primary: '#0A84FF',
  bg: '#161618',
  surface: '#232326',
  surfaceSelected: '#2E2E33',
  textPrimary: '#E8E8EA',
  textSecondary: '#A0A0A4',
  textTertiary: '#6E6E72',
  border: '#333337',
  error: '#FF453A',
  errorBg: '#3A1E1D',
  success: '#30D158',
  successBg: '#1D3A24',
  warning: '#FF9F0A',
  codeText: '#D6D6D6',
  codeBg: '#1E1E20',
  codeMuted: '#6E6E72',
  diffAdd: '#3FB950',
  diffDelete: '#F85149',
  bubbleUserText: '#FFFFFF'
};

// 按明暗取调色板
export function paletteOf(isDark: boolean): PaletteColors {
  return isDark ? DARK : LIGHT;
}

// '#RRGGBB' → 0xFFRRGGBB（ARGB number，给 markdown_hybrid 的 theme setter）。
// 用加法（0xFF000000 + rgb）规避位运算产生的负数，保持与既有 0xFFxxxxxx 字面量同形（正数）。
export function toArgb(hex: string): number {
  const clean: string = hex.startsWith('#') ? hex.substring(1) : hex;
  const rgb: number = parseInt(clean, 16);
  return 0xFF000000 + rgb;
}
