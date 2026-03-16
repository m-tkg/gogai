import { Hono } from 'hono'
import { exec } from 'child_process'
import { promisify } from 'util'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const execAsync = promisify(exec)
const __dirname = dirname(fileURLToPath(import.meta.url))
// backend/src/routes/ → プロジェクトルート（3階層上）
const PROJECT_ROOT = resolve(__dirname, '../../../')

const app = new Hono()

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
