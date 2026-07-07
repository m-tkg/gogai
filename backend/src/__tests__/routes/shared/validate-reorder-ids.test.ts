import { describe, it, expect } from 'vitest'
import { AppError } from '../../../errors.js'
import { validateReorderIds } from '../../../routes/shared/validate-reorder-ids.js'

describe('validateReorderIds', () => {
  it('整数配列ならそのまま返す', () => {
    expect(validateReorderIds([3, 1, 2])).toEqual([3, 1, 2])
  })

  it('空配列も許可する', () => {
    expect(validateReorderIds([])).toEqual([])
  })

  it('配列でなければ AppError(400) を投げる', () => {
    expect(() => validateReorderIds('not-an-array')).toThrow(AppError)
    expect(() => validateReorderIds(undefined)).toThrow(AppError)
  })

  it('整数以外の要素を含む配列は AppError(400) を投げる', () => {
    expect(() => validateReorderIds([1, 'x', 3])).toThrow(AppError)
    expect(() => validateReorderIds([1.5])).toThrow(AppError)
  })
})
