import { useState } from 'react'

// HTML5 Drag & Drop による並び替えの状態管理。
// グループ・フィードの両方で使う（id を持つ任意のリストに適用可能）。
export function useDragReorder<T extends { id: number }>(onReorder: (ids: number[]) => void) {
  const [dragId, setDragId] = useState<number | null>(null)
  const [dragOverId, setDragOverId] = useState<number | null>(null)

  const handleDragStart = (id: number) => setDragId(id)

  const handleDragOver = (e: React.DragEvent, id: number) => {
    e.preventDefault()
    setDragOverId(id)
  }

  const handleDrop = (items: T[]) => {
    const from = dragId
    const to = dragOverId
    setDragId(null)
    setDragOverId(null)
    if (from === null || to === null || from === to) return

    const reordered = [...items]
    const fromIdx = reordered.findIndex(item => item.id === from)
    const toIdx = reordered.findIndex(item => item.id === to)
    if (fromIdx === -1 || toIdx === -1) return
    const [moved] = reordered.splice(fromIdx, 1)
    reordered.splice(toIdx, 0, moved)
    onReorder(reordered.map(item => item.id))
  }

  const handleDragEnd = () => {
    setDragId(null)
    setDragOverId(null)
  }

  return { dragId, dragOverId, handleDragStart, handleDragOver, handleDrop, handleDragEnd }
}
