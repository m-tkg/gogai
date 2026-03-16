import { Hono } from 'hono'
import { exec } from 'child_process'
import { promisify } from 'util'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import fetch from 'node-fetch'

const execAsync = promisify(exec)
const __dirname = dirname(fileURLToPath(import.meta.url))
// backend/src/routes/ → プロジェクトルート（3階層上）
const PROJECT_ROOT = resolve(__dirname, '../../../')

const GITHUB_REPO = 'm-tkg/gogai'
const GITHUB_BRANCH = 'main'

const app = new Hono()

app.get('/update-check', async (c) => {
  // ローカルの最新コミット
  let localSha: string
  try {
    const { stdout } = await execAsync('git rev-parse HEAD', { cwd: PROJECT_ROOT })
    localSha = stdout.trim()
  } catch (e: unknown) {
    return c.json({ error: 'git rev-parse に失敗しました' }, 500)
  }

  // GitHub API でリモートの最新コミットを取得
  let remoteSha: string
  try {
    const res = await fetch(
      `https://api.github.com/repos/${GITHUB_REPO}/commits/${GITHUB_BRANCH}`,
      { headers: { 'User-Agent': 'gogai-app' } }
    )
    if (!res.ok) throw new Error(`GitHub API: ${res.status}`)
    const data = await res.json() as { sha: string }
    remoteSha = data.sha
  } catch (e: unknown) {
    return c.json({ error: 'GitHub API の取得に失敗しました' }, 500)
  }

  return c.json({
    local: localSha,
    remote: remoteSha,
    hasUpdate: localSha !== remoteSha,
  })
})

app.post('/restart', async (c) => {
  let gitOutput = ''

  // git pull 実行
  try {
    const { stdout, stderr } = await execAsync('git pull', { cwd: PROJECT_ROOT })
    gitOutput = stdout || stderr
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    return c.json({ error: `git pull に失敗しました: ${msg}` }, 500)
  }

  // レスポンスを返してから再起動（バックエンド自身も再起動されるため非同期で遅延実行）
  setTimeout(() => {
    exec('make restart-daemon', { cwd: PROJECT_ROOT })
  }, 300)

  return c.json({ output: gitOutput.trim() })
})

export default app
