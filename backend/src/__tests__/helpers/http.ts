import type { Hono } from 'hono'

/// ルートテスト用の JSON リクエストヘルパー。
/// 各ルートテストファイルが個別に定義していた postJson/jsonReq/putJson/patchJson を集約する。
export function jsonRequest(router: Hono, path: string, body: unknown, method = 'POST') {
  return router.request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}
