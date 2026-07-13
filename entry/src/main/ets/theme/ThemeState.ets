// 主题状态（@ObservedV2 + @Trace，经 AppStorageV2 应用级共享）。
//   mode：用户偏好（light/dark/system）；isDark：解析后的实际明暗——组件统一读它驱动调色板。
//   fontScale：全局字号缩放（1.0 默认；设置页小/默认/大三档）——组件经 fs() 套用每个 fontSize。
//   仅 isDark 是 @Trace（组件依赖它），mode 仅供设置页高亮当前选项（也标 @Trace 以便切换即更新）。
//   fontScale 同标 @Trace：设置页改后全量 fontSize 即时重渲染（fs 读它建立依赖）。
// 装饰器 @ObservedV2/@Trace 为 ArkUI 全局装饰器（与 @ComponentV2 同级，无需 import）。

export type ThemeMode = 'light' | 'dark' | 'system';

@ObservedV2
export class ThemeState {
  @Trace mode: ThemeMode = 'system';
  @Trace isDark: boolean = false;
  @Trace fontScale: number = 1.0;
}
