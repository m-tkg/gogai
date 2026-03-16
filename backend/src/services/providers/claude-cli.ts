import { exec } from 'child_process'
import { promisify } from 'util'
import type { AIProvider, AIAction } from '../ai-provider.js'

const execAsync = promisify(exec)

export class ClaudeCliProvider implements AIProvider {
  async run(action: AIAction, text: string): Promise<string> {
    const prompt = buildPrompt(action, text)
    const escaped = prompt.replace(/'/g, "'\\''")
    const { stdout, stderr } = await execAsync(`claude -p '${escaped}'`, {
      timeout: 60_000,
      maxBuffer: 1024 * 1024,
    })
    if (stderr && !stdout) throw new Error(`Claude CLI error: ${stderr}`)
    return stdout.trim()
  }
}

function buildPrompt(action: AIAction, text: string): string {
  if (action === 'summarize') {
    return `以下の記事を日本語で3〜5文で要約してください。\n\n${text}`
  }
  return `以下のテキストを日本語に翻訳してください。原文の構造を保ちつつ、自然な日本語にしてください。\n\n${text}`
}
