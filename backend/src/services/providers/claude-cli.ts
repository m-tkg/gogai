import { spawn } from 'child_process'
import { openSync, closeSync } from 'fs'
import type { AIProvider, AIAction } from '../ai-provider.js'

export class ClaudeCliProvider implements AIProvider {
  async run(action: AIAction, text: string): Promise<string> {
    const prompt = buildPrompt(action, text)
    const claudePath = process.env.CLAUDE_PATH ?? `${process.env.HOME}/.local/bin/claude`

    return new Promise((resolve, reject) => {
      // stdin を /dev/null にしないと claude が TTY チェックで終了する
      const nullFd = openSync('/dev/null', 'r')
      const proc = spawn(claudePath, ['-p', prompt], {
        env: { ...process.env },
        stdio: [nullFd, 'pipe', 'pipe'],
        timeout: 60_000,
      })
      closeSync(nullFd)

      let stdout = ''
      let stderr = ''
      proc.stdout?.on('data', (d: Buffer) => { stdout += d.toString() })
      proc.stderr?.on('data', (d: Buffer) => { stderr += d.toString() })

      proc.on('close', (code) => {
        if (code !== 0 && !stdout) {
          reject(new Error(`Claude CLI error (exit ${code}): ${stderr}`))
        } else {
          resolve(stdout.trim())
        }
      })

      proc.on('error', (err) => reject(err))
    })
  }
}

function buildPrompt(action: AIAction, text: string): string {
  if (action === 'summarize') {
    return `以下の記事を日本語で3〜5文で要約してください。\n\n${text}`
  }
  return `以下のテキストを日本語に翻訳してください。原文の構造を保ちつつ、自然な日本語にしてください。\n\n${text}`
}
