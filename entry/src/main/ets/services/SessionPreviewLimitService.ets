// SessionPreviewLimitService —— 会话列表每组预览行数的响应式状态 + 持久化。
//
// 架构（镜像 TerminalToolDisplayService）：
//   @ObservedV2 SessionPreviewLimitState{@Trace limit} 经 AppStorageV2 应用级共享单例；
//   Index 读 currentLimit 传 flattenGroups（@Trace 改 → sessionRows getter 重算即时生效）。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回；无 context。
//
// 拆层：纯常量/归一化在 chat/SessionPreviewLimit.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI + PreferencesService 持久化，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import {
  DEFAULT_SESSION_PREVIEW_LIMIT,
  normalizeSessionPreviewLimit
} from '../chat/SessionPreviewLimit';

@ObservedV2
export class SessionPreviewLimitState {
  @Trace limit: number = DEFAULT_SESSION_PREVIEW_LIMIT;
}

let _state: SessionPreviewLimitState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存
export function getSessionPreviewLimitState(): SessionPreviewLimitState {
  if (_state === null) {
    _state = AppStorageV2.connect(SessionPreviewLimitState, () => new SessionPreviewLimitState())!;
  }
  return _state;
}

export class SessionPreviewLimitService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let limit: number = DEFAULT_SESSION_PREVIEW_LIMIT;
    try {
      const stored: number = await getPreferencesService().getNumber(
        PreferenceKeys.SESSION_PREVIEW_LIMIT,
        DEFAULT_SESSION_PREVIEW_LIMIT
      );
      limit = normalizeSessionPreviewLimit(stored);
    } catch (e) {
      // 读失败默认 8
    }
    getSessionPreviewLimitState().limit = limit;
  }

  // 设置页切换调：改 limit @Trace（Index sessionRows getter 即时重算）+ 持久化
  static async setLimit(limit: number): Promise<void> {
    const normalized: number = normalizeSessionPreviewLimit(limit);
    getSessionPreviewLimitState().limit = normalized;
    try {
      await getPreferencesService().putNumber(PreferenceKeys.SESSION_PREVIEW_LIMIT, normalized);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentLimit(): number {
    return getSessionPreviewLimitState().limit;
  }
}
