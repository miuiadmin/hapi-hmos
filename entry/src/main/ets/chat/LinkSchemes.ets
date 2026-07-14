// 非 HTTP scheme 自动链接列表（无 @kit，LocalUnit 可测）。
//
// 背景：CJMarkdown plugin.setIsLinkifyPlugin(enable, schemes) 第二参为「额外自动链接的自定义 scheme 数组」
//   （http/https 由第一参 boolean 默认启用，无需列入）。上游 web/src/lib/remark-non-https-autolink.ts
//   无 allowlist——正则匹配任意 [a-zA-Z][a-zA-Z0-9+\-.]*://（非 http/https）转链接节点。
//  鸿蒙 CJMarkdown 无 MDAST hook，文本预处理匹配任意 scheme 会污染代码块/既有链接（同 M1/M2 风险），
//   故采用「慷慨显式列表」覆盖常见 scheme：faithfulness gap（显式 vs 上游任意）注明，安全靠下游
//   classifyScheme（utils/ExternalLink.ets：IANA 直开 / deny 拦 / custom 首次确认 + allowlist 持久化）。
//
// 点击成链后仍走既有 setLinkCallback → openExternal → classifyScheme，行为不变。

// 额外自动链接的 scheme（不含 http/https/mailto 这类 CJMarkdown 默认已处理的）。
//   对照上游常见用法 + ExternalLink 的 IANA/deny/custom 分类：deny 类（javascript/data/vbscript/file）永不入列。
export const NON_HTTPS_LINKIFY_SCHEMES: string[] = [
  // —— 上游 hapi 生态 agent scheme ——
  'gemini',
  'cursor',
  'opencode',
  'codex',
  // —— 常见工具/协议 scheme（custom 首次确认后入 allowlist）——
  'obsidian',
  'ftp',
  'sftp',
  'ssh',
  'telnet',
  'slack',
  'linear',
  'vscode',
  'jetbrains',
  'zoommtg',
  'notion',
  // —— IANA 安全 scheme（classifyScheme 归 iana 直开；显式列入确保 bare 串也成链）——
  'irc',
  'ircs',
  'xmpp',
  'tel'
];

// 是否含某 scheme（数组 indexOf，ArkTS strict 安全）。
export function isLinkifyScheme(scheme: string): boolean {
  return NON_HTTPS_LINKIFY_SCHEMES.indexOf(scheme) >= 0;
}
