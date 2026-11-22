import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import adminRouter from '../../routes/admin.js'

// admin ルートは promisify(exec) を使うため、callback 形式の exec をモックする。
// デフォルトの promisify は cb(err, value) の value をそのまま resolve するので、
// { stdout, stderr } オブジェクトを渡せば実装側の分割代入と互換になる。
const execMock = vi.hoisted(() => vi.fn())

vi.mock('child_process', () => ({
  exec: execMock,
}))

type ExecCallback = (err: Error | null, result?: { stdout: string; stderr: string }) => void

function mockExecResults(results: Record<string, { stdout?: string; error?: Error }>) {
  execMock.mockImplementation((cmd: string, _opts: unknown, cb: ExecCallback) => {
    for (const [pattern, result] of Object.entries(results)) {
      if (cmd.includes(pattern)) {
        if (result.error) return cb(result.error)
        return cb(null, { stdout: result.stdout ?? '', stderr: '' })
      }
    }
    cb(new Error(`unexpected command: ${cmd}`))
  })
}

let exitSpy: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  vi.clearAllMocks()
  vi.useFakeTimers()
  exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => undefined) as never)
})

afterEach(() => {
  vi.runOnlyPendingTimers()
  vi.useRealTimers()
  exitSpy.mockRestore()
})

describe('admin ルート（HTTP 契約）', () => {
  describe('GET /update-check', () => {
    it('local / remote / hasUpdate を返す（更新なし）', async () => {
      mockExecResults({
        'rev-parse HEAD': { stdout: 'abc123\n' },
        'fetch origin': { stdout: '' },
        'rev-parse origin/main': { stdout: 'abc123\n' },
      })
      const res = await adminRouter.request('/update-check')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual({ local: 'abc123', remote: 'abc123', hasUpdate: false })
    })

    it('リモートが進んでいれば hasUpdate: true を返す', async () => {
      mockExecResults({
        'rev-parse HEAD': { stdout: 'abc123\n' },
        'fetch origin': { stdout: '' },
        'rev-parse origin/main': { stdout: 'def456\n' },
      })
      const res = await adminRouter.request('/update-check')
      expect((await res.json()).hasUpdate).toBe(true)
    })

    it('git 失敗時は 500 で { error } を返す', async () => {
      mockExecResults({
        'rev-parse HEAD': { error: new Error('not a git repo') },
      })
      const res = await adminRouter.request('/update-check')
      expect(res.status).toBe(500)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('リモート取得失敗時は 500 で { error } を返す', async () => {
      mockExecResults({
        'rev-parse HEAD': { stdout: 'abc123\n' },
        'fetch origin': { error: new Error('network unreachable') },
      })
      const res = await adminRouter.request('/update-check')
      expect(res.status).toBe(500)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('git fetch は known_hosts 未登録でも失敗しないよう GIT_SSH_COMMAND 付きで実行する', async () => {
      const receivedOpts: Record<string, unknown>[] = []
      execMock.mockImplementation((cmd: string, opts: Record<string, unknown>, cb: ExecCallback) => {
        if (cmd.includes('fetch origin')) receivedOpts.push(opts)
        if (cmd.includes('rev-parse HEAD')) return cb(null, { stdout: 'abc123\n', stderr: '' })
        if (cmd.includes('fetch origin')) return cb(null, { stdout: '', stderr: '' })
        if (cmd.includes('rev-parse origin/main')) return cb(null, { stdout: 'abc123\n', stderr: '' })
        cb(new Error(`unexpected command: ${cmd}`))
      })

      await adminRouter.request('/update-check')

      expect(receivedOpts).toHaveLength(1)
      expect(receivedOpts[0]?.env).toMatchObject({
        GIT_SSH_COMMAND: 'ssh -o StrictHostKeyChecking=no -o BatchMode=yes',
      })
    })
  })

  describe('POST /restart', () => {
    it('git pull + ビルド成功で { output } を返し、500ms 後に exit する', async () => {
      mockExecResults({
        'git pull': { stdout: 'Already up to date.\n' },
        'npm run build': { stdout: 'built\n' },
      })
      const res = await adminRouter.request('/restart', { method: 'POST' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.output).toContain('Already up to date.')
      expect(exitSpy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(500)
      expect(exitSpy).toHaveBeenCalledWith(0)
    })

    it('git pull 失敗時は 500 で { error } を返し exit しない', async () => {
      mockExecResults({
        'git pull': { error: new Error('merge conflict') },
      })
      const res = await adminRouter.request('/restart', { method: 'POST' })
      expect(res.status).toBe(500)
      expect((await res.json()).error).toBeTypeOf('string')
      vi.advanceTimersByTime(1000)
      expect(exitSpy).not.toHaveBeenCalled()
    })

    it('ビルド失敗時は 500 で { error } を返し exit しない', async () => {
      mockExecResults({
        'git pull': { stdout: 'ok\n' },
        'npm run build': { error: new Error('tsc error') },
      })
      const res = await adminRouter.request('/restart', { method: 'POST' })
      expect(res.status).toBe(500)
      expect((await res.json()).error).toContain('ビルドに失敗しました')
      vi.advanceTimersByTime(1000)
      expect(exitSpy).not.toHaveBeenCalled()
    })
  })

  describe('認証（ADMIN_SECRET）', () => {
    const ORIGINAL_SECRET = process.env.ADMIN_SECRET

    afterEach(() => {
      if (ORIGINAL_SECRET === undefined) delete process.env.ADMIN_SECRET
      else process.env.ADMIN_SECRET = ORIGINAL_SECRET
    })

    it('ADMIN_SECRET 未設定なら拒否する（fail-closed）。コマンドは実行しない', async () => {
      delete process.env.ADMIN_SECRET
      for (const [path, method] of [['/update-check', 'GET'], ['/restart', 'POST']] as const) {
        const res = await adminRouter.request(path, { method })
        expect(res.status).toBe(403)
        expect((await res.json()).error).toBeTypeOf('string')
      }
      expect(execMock).not.toHaveBeenCalled()
    })

    it('ADMIN_SECRET 未設定なら、ヘッダーを付けても（空文字含む）拒否する', async () => {
      delete process.env.ADMIN_SECRET
      for (const header of ['', 'undefined', 'anything']) {
        const res = await adminRouter.request('/update-check', { headers: { 'X-Admin-Secret': header } })
        expect(res.status).toBe(403)
      }
      expect(execMock).not.toHaveBeenCalled()
    })

    it('ADMIN_SECRET が空文字なら未設定と同様に拒否する（空ヘッダーでも通らない）', async () => {
      process.env.ADMIN_SECRET = ''
      const res = await adminRouter.request('/restart', { method: 'POST', headers: { 'X-Admin-Secret': '' } })
      expect(res.status).toBe(403)
      expect(execMock).not.toHaveBeenCalled()
    })

    it('ADMIN_SECRET が空白のみなら未設定と同様に拒否する', async () => {
      process.env.ADMIN_SECRET = '   '
      const res = await adminRouter.request('/update-check', { headers: { 'X-Admin-Secret': '   ' } })
      expect(res.status).toBe(403)
      expect(execMock).not.toHaveBeenCalled()
    })

    it('不一致（長さ違い・前方一致）は 401 でコマンドを実行しない', async () => {
      process.env.ADMIN_SECRET = 'test-secret'
      for (const header of ['test-secre', 'test-secret-x', 'TEST-SECRET']) {
        const res = await adminRouter.request('/restart', { method: 'POST', headers: { 'X-Admin-Secret': header } })
        expect(res.status).toBe(401)
      }
      expect(execMock).not.toHaveBeenCalled()
    })

    it('ADMIN_SECRET 設定時、ヘッダーなしは 401 で { error } を返す', async () => {
      process.env.ADMIN_SECRET = 'test-secret'
      const res = await adminRouter.request('/update-check')
      expect(res.status).toBe(401)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('ADMIN_SECRET 設定時、誤ったヘッダーは 401 を返す', async () => {
      process.env.ADMIN_SECRET = 'test-secret'
      const res = await adminRouter.request('/update-check', {
        headers: { 'X-Admin-Secret': 'wrong' },
      })
      expect(res.status).toBe(401)
    })

    it('ADMIN_SECRET 設定時、正しいヘッダーなら通る', async () => {
      process.env.ADMIN_SECRET = 'test-secret'
      mockExecResults({
        'rev-parse HEAD': { stdout: 'abc123\n' },
        'fetch origin': { stdout: '' },
        'rev-parse origin/main': { stdout: 'abc123\n' },
      })
      const res = await adminRouter.request('/update-check', {
        headers: { 'X-Admin-Secret': 'test-secret' },
      })
      expect(res.status).toBe(200)
    })

    it('POST /restart にも同様に認証がかかる', async () => {
      process.env.ADMIN_SECRET = 'test-secret'
      const res = await adminRouter.request('/restart', { method: 'POST' })
      expect(res.status).toBe(401)
    })
  })
})
