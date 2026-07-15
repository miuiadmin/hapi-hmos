// JwtUtils 纯逻辑单测 —— JWT payload.exp 解码（对照 web useAuth.ts decodeJwtExpMs）。
// 纯层（零 @kit，LocalUnit 可加载）。覆盖合法 exp→exp*1000、多 claim、unicode payload、
//   以及各失败路径→0（无点分隔、空 payload、无 exp、exp 非数字、base64 损坏）。

import { describe, it, expect } from '@ohos/hypium';
import { decodeJwtExpMs } from '../main/ets/utils/JwtUtils';

// 组装一个三段式 token：dummy header + payload + dummy signature。
function jwt(payload: string): string {
  return `aaa.${payload}.bbb`;
}

export default function jwtUtilsTest(): void {
  describe('decodeJwtExpMs', () => {
    // 合法 exp → exp*1000（payload 仅 exp）
    it('decodes exp to epoch-ms', 0, () => {
      // payload = base64url({"exp": 1700000000})
      expect(decodeJwtExpMs(jwt('eyJleHAiOiAxNzAwMDAwMDAwfQ'))).assertEqual(1700000000000);
    });
    // 多 claim payload：仍取 exp（忽略 sub/iat）
    it('extracts exp from a multi-claim payload', 0, () => {
      // payload = base64url({"sub": "abc", "exp": 1700000000, "iat": 1699000000})
      expect(decodeJwtExpMs(jwt('eyJzdWIiOiAiYWJjIiwgImV4cCI6IDE3MDAwMDAwMCIsICJpYXQiOiAxNjk5MDAwMDAwfQ')))
        .assertEqual(1700000000000);
    });
    // exp 是字符串（非 number）→ 0
    it('returns 0 when exp is a string', 0, () => {
      // payload = base64url({"exp": "1700000000"})
      expect(decodeJwtExpMs(jwt('eyJleHAiOiAiMTcwMDAwMDAwMCJ9'))).assertEqual(0);
    });
    // 无 exp claim → 0
    it('returns 0 when exp is absent', 0, () => {
      // payload = base64url({"sub": "abc"})
      expect(decodeJwtExpMs(jwt('eyJzdWIiOiAiYWJjIn0'))).assertEqual(0);
    });
    // 非 ASCII（\uXXXX 转义，ASCII 字节）payload 仍取 exp
    it('decodes exp from a payload with \\uXXXX escapes', 0, () => {
      // payload = base64url({"name": "用户", "exp": 1700000000})
      expect(decodeJwtExpMs(jwt('eyJuYW1lIjogIlx1NzUyOFx1NjIzNyIsICJleHAiOiAxNzAwMDAwMDAwfQ')))
        .assertEqual(1700000000000);
    });
    // 真实多字节 UTF-8（用户）payload：UTF-8 解码正确后取 exp（覆盖 3 字节序列路径）
    it('decodes exp from a raw multibyte UTF-8 payload', 0, () => {
      // payload = base64url(utf-8({"name":"用户","exp":1700000000}))
      expect(decodeJwtExpMs(jwt('eyJuYW1lIjogIueUqOaItyIsICJleHAiOiAxNzAwMDAwMDAwfQ')))
        .assertEqual(1700000000000);
    });
    // 无 '.' 分隔 → 0
    it('returns 0 when there is no dot', 0, () => {
      expect(decodeJwtExpMs('abc')).assertEqual(0);
    });
    // 空串 → 0
    it('returns 0 for empty token', 0, () => {
      expect(decodeJwtExpMs('')).assertEqual(0);
    });
    // payload 段为空（仅一个点，payload 在 dot 与 dot 之间为空）→ 0
    it('returns 0 when payload segment is empty', 0, () => {
      expect(decodeJwtExpMs('aaa..bbb')).assertEqual(0);
    });
    // base64 损坏（非法字符 !）→ 解码抛错 → catch → 0
    it('returns 0 for corrupt base64 payload', 0, () => {
      expect(decodeJwtExpMs(jwt('!!!@@@'))).assertEqual(0);
    });
  });
}
