import { describe, it, expect } from 'vitest'
import { parseNonNegativeInt } from '../routes/articles.js'

describe('parseNonNegativeInt', () => {
  it('undefined はデフォルト値を返す', () => {
    expect(parseNonNegativeInt(undefined, 50)).toBe(50)
  })

  it('数字文字列をパースして返す', () => {
    expect(parseNonNegativeInt('100', 50)).toBe(100)
    expect(parseNonNegativeInt('0', 50)).toBe(0)
  })

  it('非数値文字列はデフォルト値を返す（NaN ガード）', () => {
    expect(parseNonNegativeInt('abc', 50)).toBe(50)
    expect(parseNonNegativeInt('', 50)).toBe(50)
  })

  it('負の値はデフォルト値を返す', () => {
    expect(parseNonNegativeInt('-5', 50)).toBe(50)
  })

  it('max を超える値は max にクランプする', () => {
    expect(parseNonNegativeInt('99999', 50, 1000)).toBe(1000)
    expect(parseNonNegativeInt('500', 50, 1000)).toBe(500)
  })
})
