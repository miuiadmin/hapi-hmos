// 运行时权限申请（语音页麦克风）。
//   ArkWeb Web 组件内 getUserMedia 要走通，必须先拿到系统级 ohos.permission.MICROPHONE
//   （berry3 Index.ets L9695 注释：onPermissionRequest 的 grant() 只放行 ArkWeb 层页面权限；
//    若 app 自身无系统麦克风授权，getUserMedia 仍抛 NotAllowedError）。
//   本工具先查已授予态（免重复弹窗），未授予再 requestPermissionsFromUser。
//   仅参考 berry3 PermissionUtils 思路，自写最小版（berry3 license 不明，不搬代码）。

import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const PERMISSION_GRANTED: number = 0;   // GrantStatus.PERMISSION_GRANTED

// 确保麦克风已授权：已授予直返 true；否则弹系统授权窗，按用户选择返回。
//   失败/拒绝统一返 false（调用方据此进「未授权」错误态，不抛错）。
export async function ensureMicrophonePermission(context: common.UIAbilityContext): Promise<boolean> {
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  // 先查当前授予态：已授予直接返回，免重复弹窗
  let tokenId: number = 0;
  try {
    tokenId = context.applicationInfo.accessTokenId;
  } catch (_e) {
    tokenId = 0;
  }
  if (tokenId !== 0) {
    try {
      const status: number = await atManager.checkAccessToken(tokenId, MICROPHONE_PERMISSION);
      if (status === PERMISSION_GRANTED) {
        return true;
      }
    } catch (_e) {
      // 查询失败：降级走请求弹窗
    }
  }

  // 发起系统授权弹窗
  try {
    const result: abilityAccessCtrl.PermissionRequestResult =
      await atManager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
    if (result.authResults.length === 0) {
      return false;
    }
    return result.authResults[0] === PERMISSION_GRANTED;
  } catch (_e) {
    return false;
  }
}
