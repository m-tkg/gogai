import { Hono } from 'hono'
import { exec } from 'child_process'
import { promisify } from 'util'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const execAsync = promisify(exec)
const __dirname = dirname(fileURLToPath(import.meta.url))
// backend/src/routes/ → プロジェクトルート（3階層上）
const PROJECT_ROOT = resolve(__dirname, '../../../')

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

  // git fetch でリモートの最新コミットを取得（GitHub API 不使用・既存認証情報を利用）
  let remoteSha: string
  try {
    await execAsync(`git fetch origin ${GITHUB_BRANCH} --quiet`, { cwd: PROJECT_ROOT })
    const { stdout } = await execAsync(`git rev-parse origin/${GITHUB_BRANCH}`, { cwd: PROJECT_ROOT })
    remoteSha = stdout.trim()
  } catch (e: unknown) {
    return c.json({ error: 'リモートの取得に失敗しました' }, 500)
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
  // GIT_SSH_COMMAND: known_hosts 未登録でも失敗せず、対話入力なしで動作させる
  try {
    const { stdout, stderr } = await execAsync('git pull', {
      cwd: PROJECT_ROOT,
      env: {
        ...process.env,
        GIT_SSH_COMMAND: 'ssh -o StrictHostKeyChecking=no -o BatchMode=yes',
      },
    })
    gitOutput = stdout || stderr
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[restart] git pull failed:', msg)
    return c.json({ error: msg }, 500)
  }

  // レスポンスを返してからプロセスを終了する
  // systemd の Restart=always により自動再起動 → ExecStartPre の npm run build で新コードをビルド
  setTimeout(() => process.exit(0), 1000)

  return c.json({ output: gitOutput.trim() })
})

export default app
