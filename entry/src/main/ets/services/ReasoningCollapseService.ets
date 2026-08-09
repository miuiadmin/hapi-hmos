// ReasoningCollapseService —— 「推理默认折叠」全局开关的响应式状态 + 持久化。
//
// 对照上游 v0.27.2 #1385（web/src/hooks/useReasoningCollapse.ts）：
//   DEFAULT_REASONING_COLLAPSED = false（默认关 → 保留「流式中自动展开」旧行为）。
//   开启后（true）：推理块即使流式中也保持折叠（ReasoningBubble 的 shouldExpand 门控 isStreaming）。
//
// 架构（镜像 HapticService 的布尔态范式，简化版——纯 bool 无 'on'/'off' 串归一，
//   直接 getBoolean/putBoolean）：@ObservedV2 ReasoningCollapseState{@Trace collapsedByDefault}
//   经 AppStorageV2 应用级共享单例；ReasoningBubble 读 getReasoningCollapseState().collapsedByDefault
//   建立刷新依赖；ChatSettingsPage 切换 setCollapsed → 改 @Trace → 即时重渲染。init 在
//   EntryAbility.bootstrap（loadContent 前）从 Preferences 读回。无 context（纯 state + 持久化）。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';

// 默认不强制折叠（对照上游 DEFAULT_REASONING_COLLAPSED = false）
export const DEFAULT_REASONING_COLLAPSED: boolean = false;

@ObservedV2
export class ReasoningCollapseState {
  @Trace collapsedByDefault: boolean = DEFAULT_REASONING_COLLAPSED;
}

let _state: ReasoningCollapseState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getHapticsState）
export function getReasoningCollapseState(): ReasoningCollapseState {
  if (_state === null) {
    _state = AppStorageV2.connect(ReasoningCollapseState, () => new ReasoningCollapseState())!;
  }
  return _state;
}

export class ReasoningCollapseService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let collapsed = DEFAULT_REASONING_COLLAPSED;
    try {
      collapsed = await getPreferencesService().getBoolean(
        PreferenceKeys.REASONING_COLLAPSED_BY_DEFAULT,
        DEFAULT_REASONING_COLLAPSED
      );
    } catch (e) {
      // 读失败用默认值
    }
    getReasoningCollapseState().collapsedByDefault = collapsed;
  }

  // 设置页切换调：改 collapsedByDefault @Trace + 持久化
  static async setCollapsed(collapsed: boolean): Promise<void> {
    getReasoningCollapseState().collapsedByDefault = collapsed;
    try {
      await getPreferencesService().putBoolean(PreferenceKeys.REASONING_COLLAPSED_BY_DEFAULT, collapsed);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentCollapsed(): boolean {
    return getReasoningCollapseState().collapsedByDefault;
  }
}
