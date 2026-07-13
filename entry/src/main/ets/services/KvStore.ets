// 键值存储抽象接口（@kit-free）。
//
// 供纯逻辑模块（chat/Skills、utils/ExternalLink）依赖 —— 避免它们直接 import PreferencesService
// 而在模块加载期拉入 @kit.ArkData/@kit.AbilityKit，破坏 LocalUnit「纯逻辑无 @kit」不变量
// （import { x } from './Y' 会令 Y 顶层 @kit import 在加载期求值，即便 x 从未被调用）。
//
// 调用方（UI 文件，本身已 @kit 合法）注入 getPreferencesService()：PreferencesService implements KvStore。
// 这是已确立的「拆纯层」模式（同 Translate/I18nService、HubClientUtils/HubClient）：
//   - 纯逻辑侧只依赖本接口（@kit-free），单测可注入 FakeKvStore 或只测纯 parse/merge 函数；
//   - @kit 只停在注入边界（UI → PreferencesService）。
export interface KvStore {
  getString(key: string, defaultValue: string): Promise<string>;
  putString(key: string, value: string): Promise<void>;
}
