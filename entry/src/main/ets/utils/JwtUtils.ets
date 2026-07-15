// JWT 解码纯逻辑（对照上游 web useAuth.ts decodeJwtExpMs）。
//   纯函数层（零 @kit）——base64url + UTF-8 解码全部手写，可直接 LocalUnit 测（@kit.ArkTS util 在 LocalUnit 不可用）。
//   禁 regex / replace 回调（漏匹配）→ 字符循环 + 查表；禁 split 数组 → indexOf 取 payload 段。
//
//   decodeJwtExpMs：token.payload.exp → epoch-ms（exp*1000）。不可解析 / 无点分隔 / 无 exp / exp 非数字 /
//     base64 损坏 → 0（调用方按 0 = 「无有效 exp」，不排程刷新；被动 401 刷新仍兜底）。

// 标准 base64 字母表（查表替 char→6bit 计算；indexOf 避 Record 反查的运行时初始化）。
const B64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function decodeJwtExpMs(token: string): number {
  // 取 payload：第一个 '.' 与第二个 '.' 之间（无尾随签名段时取到串尾）。避 split 数组。
  const firstDot: number = token.indexOf('.');
  if (firstDot < 0) { return 0; }
  const secondDot: number = token.indexOf('.', firstDot + 1);
  const payloadEnd: number = secondDot < 0 ? token.length : secondDot;
  const payloadB64Url: string = token.substring(firstDot + 1, payloadEnd);
  if (payloadB64Url === '') { return 0; }
  try {
    const json: string = base64UrlDecodeToString(payloadB64Url);
    const payload = JSON.parse(json) as Record<string, Object>;
    const expRaw: Object = payload['exp'];
    if (typeof expRaw !== 'number') { return 0; }
    const exp: number = expRaw;
    return exp * 1000;
  } catch (e) {
    return 0;
  }
}

// base64url → UTF-8 字符串：先 url→standard 字符映射（'-' → '+'，'_' → '/'，末尾补 '=' 到 4 倍数），
//   再 standard base64 → 字节（4 char → 3 byte，'=' 截断），再 UTF-8 解码为字符串。
function base64UrlDecodeToString(s: string): string {
  let std: string = '';
  for (let i = 0; i < s.length; i++) {
    const ch: string = s.charAt(i);
    if (ch === '-') { std += '+'; }
    else if (ch === '_') { std += '/'; }
    else { std += ch; }
  }
  const pad: number = (4 - (std.length % 4)) % 4;
  for (let i = 0; i < pad; i++) { std += '='; }
  const bytes: number[] = base64ToBytes(std);
  return utf8Decode(bytes);
}

// standard base64 → 字节数组。按 4 字符一组解出 1–3 字节；'-'/'_' 已映射，此处只处理 '+'/'/' 与 '=' 填充。
//   c0/c1 必为数据字符（填充只在末组的 c2/c3）；任一非填充字符查表失败 → 抛错（上层 catch → 0）。
function base64ToBytes(std: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < std.length; i += 4) {
    const v0: number = B64_ALPHABET.indexOf(std.charAt(i));
    const v1: number = B64_ALPHABET.indexOf(std.charAt(i + 1));
    const c2Pad: boolean = std.charAt(i + 2) === '=';
    const c3Pad: boolean = std.charAt(i + 3) === '=';
    const v2: number = c2Pad ? 0 : B64_ALPHABET.indexOf(std.charAt(i + 2));
    const v3: number = c3Pad ? 0 : B64_ALPHABET.indexOf(std.charAt(i + 3));
    if (v0 < 0 || v1 < 0 || (!c2Pad && v2 < 0) || (!c3Pad && v3 < 0)) {
      throw new Error('bad base64');
    }
    out.push((v0 << 2) | (v1 >> 4));
    if (!c2Pad) {
      out.push(((v1 & 0x0F) << 4) | (v2 >> 2));
      if (!c3Pad) {
        out.push(((v2 & 0x03) << 6) | v3);
      }
    }
  }
  return out;
}

// 字节序列 → UTF-8 字符串（手写，对照 util.TextDecoder.decodeToString('utf-8')）。
//   支持 1–4 字节序列；4 字节（>U+FFFF）走代理对。不完整/非法序列按单字节透传（JWT payload 几乎全 ASCII）。
function utf8Decode(bytes: number[]): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if ((b0 & 0xE0) === 0xC0 && i + 1 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0 && i + 2 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0 && i + 3 < bytes.length) {
      const cp: number = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      const adj: number = cp - 0x10000;
      out += String.fromCharCode(0xD800 | (adj >> 10));
      out += String.fromCharCode(0xDC00 | (adj & 0x3FF));
      i += 4;
    } else {
      out += String.fromCharCode(b0);
      i += 1;
    }
  }
  return out;
}
