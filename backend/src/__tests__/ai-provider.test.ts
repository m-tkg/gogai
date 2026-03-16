import { describe, it, expect, afterEach } from 'vitest'
import { vi } from 'vitest'
import { getAIProvider } from '../services/ai-provider.js'

afterEach(() => vi.unstubAllEnvs())

describe('getAIProvider (factory)', () => {
  it('provider が claude の場合 run メソッドを持つオブジェクトを返す', () => {
    const provider = getAIProvider({ provider: 'claude' })
    expect(typeof provider.run).toBe('function')
  })

  it('provider が openai の場合 run メソッドを持つオブジェクトを返す', () => {
    vi.stubEnv('OPENAI_API_KEY', 'test-key')
    const provider = getAIProvider({ provider: 'openai', model: 'gpt-4o-mini' })
    expect(typeof provider.run).toBe('function')
  })

  it('provider が gemini の場合 run メソッドを持つオブジェクトを返す', () => {
    vi.stubEnv('GEMINI_API_KEY', 'test-key')
    const provider = getAIProvider({ provider: 'gemini', model: 'gemini-2.0-flash' })
    expect(typeof provider.run).toBe('function')
  })

  it('デフォルトモデルが設定される（openai）', () => {
    vi.stubEnv('OPENAI_API_KEY', 'test-key')
    // model 未指定でもエラーなくインスタンス化できる
    const provider = getAIProvider({ provider: 'openai' })
    expect(typeof provider.run).toBe('function')
  })

  it('不明なプロバイダーはエラーを投げる', () => {
    expect(() => getAIProvider({ provider: 'unknown' as never })).toThrow('Unknown AI provider')
  })
})
