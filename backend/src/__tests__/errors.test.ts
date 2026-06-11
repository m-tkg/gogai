import { describe, it, expect, vi } from 'vitest'
import { Hono } from 'hono'
import Database from 'better-sqlite3'
import { AppError, errorHandler, isUniqueConstraintError } from '../errors.js'

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

describe('isUniqueConstraintError', () => {
  it('better-sqlite3 の UNIQUE 制約違反を判定できる', () => {
    const db = new Database(':memory:')
    db.exec('CREATE TABLE t (name TEXT UNIQUE)')
    db.prepare('INSERT INTO t (name) VALUES (?)').run('a')
    let caught: unknown
    try {
      db.prepare('INSERT INTO t (name) VALUES (?)').run('a')
    } catch (e) {
      caught = e
    }
    db.close()
    expect(isUniqueConstraintError(caught)).toBe(true)
  })

  it('他のエラーや非 Error は false を返す', () => {
    expect(isUniqueConstraintError(new Error('something else'))).toBe(false)
    expect(isUniqueConstraintError('string')).toBe(false)
    expect(isUniqueConstraintError(null)).toBe(false)
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

  it('Error 以外の値も 500 で { error: string } を返す（Hono は非 Error を onError に渡さないため直接検証）', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const fakeContext = {
      req: { method: 'GET', path: '/' },
      json: (body: unknown, status: number) => Response.json(body, { status }),
    } as unknown as Parameters<typeof errorHandler>[1]
    const res = errorHandler('string error', fakeContext)
    expect(res.status).toBe(500)
    const body = await res.json()
    expect(body.error).toBeTypeOf('string')
    spy.mockRestore()
  })
})
