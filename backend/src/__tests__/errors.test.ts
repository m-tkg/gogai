import { describe, it, expect, vi } from 'vitest'
import { Hono } from 'hono'
import { AppError, errorHandler } from '../errors.js'

describe('AppError', () => {
  it('message と status を保持する', () => {
    const e = new AppError('Not found', 404)
    expect(e.message).toBe('Not found')
    expect(e.status).toBe(404)
    expect(e).toBeInstanceOf(Error)
  })

  it('status を省略すると 500 になる', () => {
    expect(new AppError('boom').status).toBe(500)
  })
})

describe('errorHandler', () => {
  function appThatThrows(error: unknown) {
    const app = new Hono()
    app.onError(errorHandler)
    app.get('/', () => {
      throw error
    })
    return app
  }

  it('AppError は status と { error: message } に変換する', async () => {
    const res = await appThatThrows(new AppError('Feed URL already exists', 409)).request('/')
    expect(res.status).toBe(409)
    expect(await res.json()).toEqual({ error: 'Feed URL already exists' })
  })

  it('予期しない Error は 500 で { error: message } を返す', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const res = await appThatThrows(new Error('unexpected')).request('/')
    expect(res.status).toBe(500)
    expect(await res.json()).toEqual({ error: 'unexpected' })
    expect(spy).toHaveBeenCalled()
    spy.mockRestore()
  })

  it('Error 以外の throw も 500 で { error: string } を返す', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const res = await appThatThrows('string error').request('/')
    expect(res.status).toBe(500)
    const body = await res.json()
    expect(body.error).toBeTypeOf('string')
    spy.mockRestore()
  })
})
