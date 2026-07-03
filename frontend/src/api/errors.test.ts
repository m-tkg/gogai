import { describe, it, expect } from 'vitest'
import { getApiErrorMessage } from './errors'

describe('getApiErrorMessage', () => {
  it('axios エラーの response.data.error を返す', () => {
    const e = { response: { data: { error: 'Feed URL already exists' } } }
    expect(getApiErrorMessage(e, 'fallback')).toBe('Feed URL already exists')
  })

  it('error フィールドがなければ fallback を返す', () => {
    expect(getApiErrorMessage({ response: { data: {} } }, 'fallback')).toBe('fallback')
    expect(getApiErrorMessage(new Error('boom'), 'fallback')).toBe('fallback')
    expect(getApiErrorMessage(null, 'fallback')).toBe('fallback')
    expect(getApiErrorMessage({ response: { data: { error: 123 } } }, 'fallback')).toBe('fallback')
  })
})
