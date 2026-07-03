/**
 * setInterval などで unhandled rejection になりがちな async 関数を安全に実行する。
 * 失敗時は console.error にログを残し、呼び出し側に例外を伝播させない。
 */
export async function runSafely<T>(label: string, fn: () => Promise<T> | T): Promise<T | void> {
  try {
    return await fn()
  } catch (err) {
    console.error(`[${label}] unexpected error:`, err)
  }
}
