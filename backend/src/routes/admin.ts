import { Hono } from 'hono'
import { exec } from 'child_process'
import { promisify } from 'util'
import { resolve, join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { AppError, errorHandler } from '../errors.js'

const execAsync = promisify(exec)
const __dirname = dirname(fileURLToPath(import.meta.url))
// backend/src/routes/ → プロジェクトルート（3階層上）
const PROJECT_ROOT = resolve(__dirname, '../../../')
const BACKEND_DIR = join(PROJECT_ROOT, 'backend')

const GITHUB_BRANCH = 'main'

const app = new Hono()
app.onError(errorHandler)

// git pull・npm run build・プロセス再起動という強い権限操作のため、ADMIN_SECRET が
// 設定されていれば X-Admin-Secret ヘッダーでの認証を必須にする。
// opt-in: 未設定の既存デプロイを壊さないよう、未設定時は従来通り無認証で通す。
app.use('*', async (c, next) => {
  const secret = process.env.ADMIN_SECRET
  if (!secret) {
    await next()
    return
  }
  if (c.req.header('X-Admin-Secret') !== secret) {
    throw new AppError('Unauthorized', 401)
  }
  await next()
})

app.get('/update-check', async (c) => {
  // ローカルの最新コミット
  let localSha: string
  try {
    const { stdout } = await execAsync('git rev-parse HEAD', { cwd: PROJECT_ROOT })
    localSha = stdout.trim()
  } catch (e: unknown) {
    throw new AppError('git rev-parse に失敗しました', 500)
  }

  // git fetch でリモートの最新コミットを取得（GitHub API 不使用・既存認証情報を利用）
  // GIT_SSH_COMMAND: known_hosts 未登録でも失敗せず、対話入力なしで動作させる（POST /restart の git pull と同様）
  let remoteSha: string
  try {
    await execAsync(`git fetch origin ${GITHUB_BRANCH} --quiet`, {
      cwd: PROJECT_ROOT,
      env: {
        ...process.env,
        GIT_SSH_COMMAND: 'ssh -o StrictHostKeyChecking=no -o BatchMode=yes',
      },
    })
    const { stdout } = await execAsync(`git rev-parse origin/${GITHUB_BRANCH}`, { cwd: PROJECT_ROOT })
    remoteSha = stdout.trim()
  } catch (e: unknown) {
    throw new AppError('リモートの取得に失敗しました', 500)
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
    throw new AppError(msg, 500)
  }

  // 現プロセスの PATH を引き継いで npm run build を実行する
  // （systemd の ExecStartPre は PATH が限定されて失敗する場合があるため、ここでビルドする）
  let buildOutput = ''
  try {
    const { stdout, stderr } = await execAsync('npm run build', {
      cwd: BACKEND_DIR,
      env: process.env,
    })
    buildOutput = stdout || stderr
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[restart] npm run build failed:', msg)
    throw new AppError(`ビルドに失敗しました: ${msg}`, 500)
  }

  // レスポンスを先に返し、500ms 後にプロセスを終了する
  // systemd の Restart=always により自動再起動 → dist/ はビルド済みのため即起動
  const output = [gitOutput, buildOutput].map((s) => s.trim()).filter(Boolean).join('\n---\n')
  const response = c.json({ output })
  setTimeout(() => process.exit(0), 500)
  return response
})

export default app
