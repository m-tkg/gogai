import { AppError } from '../../errors.js'

/// PATCH /reorder の body.ids を検証する。整数配列でなければ AppError(400) を投げる。
export function validateReorderIds(ids: unknown): number[] {
  if (!Array.isArray(ids) || !ids.every(Number.isInteger)) {
    throw new AppError('ids must be an array of integers', 400)
  }
  return ids
}
