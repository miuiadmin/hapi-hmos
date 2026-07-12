// Hapi 鉴权类型（对齐 hapi shared/src/apiTypes.ts）
// 登录流程：POST /api/auth { accessToken } → { token: JWT, user }
// 详见 docs/官方仓库对照.md

// 登录请求体（用 CLI_API_TOKEN 换 JWT）
export class AuthRequest {
  accessToken: string = '';
}

// 登录响应里的用户信息
export class AuthUser {
  id: number = 0;
  firstName: string = '';
}

// 登录响应（token 即签发的 JWT，4 小时过期，过期前自动重换）
export class AuthResponse {
  token: string = '';
  user: AuthUser = new AuthUser();
}
