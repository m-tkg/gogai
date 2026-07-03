import { describe, it, expect, vi } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useDragReorder } from './useDragReorder'

const items = [{ id: 1 }, { id: 2 }, { id: 3 }]

function dragEvent(): React.DragEvent {
  return { preventDefault: vi.fn() } as unknown as React.DragEvent
}

describe('useDragReorder', () => {
  it('ドラッグした項目をドロップ先の位置に挿入した順序で onReorder を呼ぶ', () => {
    const onReorder = vi.fn()
    const { result } = renderHook(() => useDragReorder(onReorder))

    act(() => result.current.handleDragStart(3))
    act(() => result.current.handleDragOver(dragEvent(), 1))
    act(() => result.current.handleDrop(items))

    expect(onReorder).toHaveBeenCalledWith([3, 1, 2])
  })

  it('同じ項目へのドロップでは onReorder を呼ばない', () => {
    const onReorder = vi.fn()
    const { result } = renderHook(() => useDragReorder(onReorder))

    act(() => result.current.handleDragStart(2))
    act(() => result.current.handleDragOver(dragEvent(), 2))
    act(() => result.current.handleDrop(items))

    expect(onReorder).not.toHaveBeenCalled()
  })

  it('ドロップ後・dragEnd 後は drag 状態がリセットされる', () => {
    const { result } = renderHook(() => useDragReorder(vi.fn()))

    act(() => result.current.handleDragStart(1))
    act(() => result.current.handleDragOver(dragEvent(), 2))
    expect(result.current.dragId).toBe(1)
    expect(result.current.dragOverId).toBe(2)

    act(() => result.current.handleDrop(items))
    expect(result.current.dragId).toBeNull()
    expect(result.current.dragOverId).toBeNull()

    act(() => result.current.handleDragStart(1))
    act(() => result.current.handleDragEnd())
    expect(result.current.dragId).toBeNull()
  })

  it('リストに存在しない id の場合は onReorder を呼ばない', () => {
    const onReorder = vi.fn()
    const { result } = renderHook(() => useDragReorder(onReorder))

    act(() => result.current.handleDragStart(99))
    act(() => result.current.handleDragOver(dragEvent(), 1))
    act(() => result.current.handleDrop(items))

    expect(onReorder).not.toHaveBeenCalled()
  })
})
