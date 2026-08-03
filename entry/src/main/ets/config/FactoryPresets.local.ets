import { ServerPreset } from '../models/HubConfig';

// 厂内测试预制服务器数据源（登录页「一键登录」芯片）。
//
// ⚠️ 机密处理：本文件可能含厂测 Hub 的 apiToken（机密）。
//   - 公开仓库中本文件恒为 **空数组**（下方 FACTORY_PRESETS = []），不含任何真值，可安全入库/公开。
//   - 本机如需一键登录：先 `git update-index --skip-worktree entry/src/main/ets/config/FactoryPresets.local.ets`
//     （让 git 忽略本文件后续本地改动），再把真值填进 FACTORY_PRESETS（见注释示例）。
//   - 真值仅存本机源码 + 装机设备，不入日志、不外传、不入 git 历史。
//
// 本机填充示例（切勿提交）：
//   export const FACTORY_PRESETS: ServerPreset[] = [
//     new ServerPreset('factory', '厂内测试', 'https://hapi.example.nip.io/', '<CLI_API_TOKEN>'),
//   ];
export const FACTORY_PRESETS: ServerPreset[] = [];
