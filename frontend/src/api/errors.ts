// axios エラーからバックエンドの { error: string } メッセージを型安全に取り出す
export function getApiErrorMessage(error: unknown, fallback: string): string {
  if (typeof error === 'object' && error !== null && 'response' in error) {
    const response = (error as { response?: { data?: { error?: unknown } } }).response
    if (typeof response?.data?.error === 'string') return response.data.error
  }
  return fallback
}
