import { ClaudeCliProvider } from './providers/claude-cli.js'
import { OpenAIProvider } from './providers/openai.js'
import { GeminiProvider } from './providers/gemini.js'

export type AIAction = 'summarize' | 'translate'

export interface AIProvider {
  run(action: AIAction, text: string): Promise<string>
}

export interface AIConfig {
  provider: 'claude' | 'openai' | 'gemini'
  model?: string
}

export function getAIProvider(config: AIConfig): AIProvider {
  switch (config.provider) {
    case 'claude':
      return new ClaudeCliProvider()
    case 'openai':
      return new OpenAIProvider(
        process.env.OPENAI_API_KEY ?? '',
        config.model ?? 'gpt-4o-mini'
      )
    case 'gemini':
      return new GeminiProvider(
        process.env.GEMINI_API_KEY ?? '',
        config.model ?? 'gemini-2.0-flash'
      )
    default:
      throw new Error(`Unknown AI provider: ${(config as AIConfig).provider}`)
  }
}
