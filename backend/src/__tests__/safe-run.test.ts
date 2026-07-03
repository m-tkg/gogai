import { describe, it, expect, vi } from 'vitest'
import { runSafely } from '../utils/safe-run.js'

describe('runSafely', () => {
  it('成功時は関数の戻り値をそのまま返す', async () => {
    await expect(runSafely('test', async () => 42)).resolves.toBe(42)
  })

  it('rejection を捕捉して console.error にログを残し、re-throw しない', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const err = new Error('boom')
    await expect(runSafely('test', async () => { throw err })).resolves.toBeUndefined()
    expect(spy).toHaveBeenCalledWith('[test] unexpected error:', err)
    spy.mockRestore()
  })

  it('同期的に throw する関数も捕捉する', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const err = new Error('sync boom')
    await expect(runSafely('test', () => { throw err })).resolves.toBeUndefined()
    expect(spy).toHaveBeenCalledWith('[test] unexpected error:', err)
    spy.mockRestore()
  })
})
