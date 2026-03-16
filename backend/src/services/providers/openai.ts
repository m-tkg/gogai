import OpenAI from 'openai'
import type { AIProvider, AIAction } from '../ai-provider.js'

export class OpenAIProvider implements AIProvider {
  private client: OpenAI

  constructor(apiKey: string, private model: string) {
    this.client = new OpenAI({ apiKey })
  }

  async run(action: AIAction, text: string): Promise<string> {
    const prompt = buildPrompt(action, text)
    const res = await this.client.chat.completions.create({
      model: this.model,
      messages: [{ role: 'user', content: prompt }],
    })
    return res.choices[0]?.message?.content?.trim() ?? ''
  }
}

function buildPrompt(action: AIAction, text: string): string {
  if (action === 'summarize') {
    return `以下の記事を日本語で3〜5文で要約してください。\n\n${text}`
  }
  return `以下のテキストを日本語に翻訳してください。原文の構造を保ちつつ、自然な日本語にしてください。\n\n${text}`
}
