import { exec } from 'child_process'
import { promisify } from 'util'

const execAsync = promisify(exec)

export type ClaudeAction = 'summarize' | 'translate'

export interface ClaudeResult {
  output: string
}

export async function runClaudeAction(action: ClaudeAction, text: string): Promise<ClaudeResult> {
  const prompt = buildPrompt(action, text)

  // claude -p "<prompt>" を実行
  const escaped = prompt.replace(/'/g, "'\\''")
  const { stdout, stderr } = await execAsync(`claude -p '${escaped}'`, {
    timeout: 60_000,
    maxBuffer: 1024 * 1024,
  })

  if (stderr && !stdout) {
    throw new Error(`Claude CLI error: ${stderr}`)
  }

  return { output: stdout.trim() }
}

function buildPrompt(action: ClaudeAction, text: string): string {
  if (action === 'summarize') {
    return `以下の記事を日本語で3〜5文で要約してください。\n\n${text}`
  }
  if (action === 'translate') {
    return `以下のテキストを日本語に翻訳してください。原文の構造を保ちつつ、自然な日本語にしてください。\n\n${text}`
  }
  throw new Error(`Unknown action: ${action}`)
}
