import type { Context } from 'hono'
import type { ContentfulStatusCode } from 'hono/utils/http-status'

// ルートハンドラから throw する業務エラー。errorHandler が { error: message } に変換する。
export class AppError extends Error {
  constructor(
    message: string,
    public readonly status: ContentfulStatusCode = 500
  ) {
    super(message)
    this.name = 'AppError'
  }
}

// 各ルーターの app.onError に渡す共通ハンドラ。
// レスポンス形式は既存契約 { error: string } を厳守する（特性テストが固定済み）。
export function errorHandler(err: unknown, c: Context): Response {
  if (err instanceof AppError) {
    return c.json({ error: err.message }, err.status)
  }
  console.error(`[${c.req.method} ${c.req.path}]`, err)
  const message = err instanceof Error ? err.message : 'Internal Server Error'
  return c.json({ error: message }, 500)
}
