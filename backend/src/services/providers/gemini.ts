import { GoogleGenerativeAI } from '@google/generative-ai'
import type { AIProvider, AIAction } from '../ai-provider.js'

export class GeminiProvider implements AIProvider {
  private genAI: GoogleGenerativeAI

  constructor(apiKey: string, private model: string) {
    this.genAI = new GoogleGenerativeAI(apiKey)
  }

  async run(action: AIAction, text: string): Promise<string> {
    const prompt = buildPrompt(action, text)
    const genModel = this.genAI.getGenerativeModel({ model: this.model })
    const result = await genModel.generateContent(prompt)
    return result.response.text().trim()
  }
}

function buildPrompt(action: AIAction, text: string): string {
  if (action === 'summarize') {
    return `以下の記事を日本語で3〜5文で要約してください。\n\n${text}`
  }
  return `以下のテキストを日本語に翻訳してください。原文の構造を保ちつつ、自然な日本語にしてください。\n\n${text}`
}
