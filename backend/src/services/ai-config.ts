import { readFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import type { AIConfig } from './ai-provider.js'

const __dirname = dirname(fileURLToPath(import.meta.url))

interface RawConfig {
  provider: AIConfig['provider']
  openai?: { model?: string }
  gemini?: { model?: string }
}

function loadConfig(): AIConfig {
  const configPath = process.env.AI_CONFIG_PATH
    ?? resolve(__dirname, '../../ai.config.json')

  let raw: RawConfig
  try {
    raw = JSON.parse(readFileSync(configPath, 'utf-8')) as RawConfig
  } catch {
    // 設定ファイルがなければ claude をデフォルトとして使用
    return { provider: 'claude' }
  }

  const model = raw.provider === 'openai'
    ? (raw.openai?.model ?? 'gpt-4o-mini')
    : raw.provider === 'gemini'
      ? (raw.gemini?.model ?? 'gemini-2.0-flash')
      : undefined

  return { provider: raw.provider, model }
}

// サーバー起動時に一度だけ読み込む
export const aiConfig: AIConfig = loadConfig()
