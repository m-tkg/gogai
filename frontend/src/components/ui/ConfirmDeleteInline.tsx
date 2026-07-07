import { confirmCancelBtn } from './formStyles'

interface ConfirmDeleteInlineProps {
  onConfirm: () => void
  onCancel: () => void
}

// グループ/フィード一覧の行内に出す「削除?」の確認 UI（インライン、モーダルなし）
export function ConfirmDeleteInline({ onConfirm, onCancel }: ConfirmDeleteInlineProps) {
  return (
    <div className="flex items-center gap-1 px-1">
      <span className="text-xs text-red-500 dark:text-red-400">削除?</span>
      <button
        onClick={onConfirm}
        className="px-1.5 py-0.5 text-xs bg-red-500 text-white rounded hover:bg-red-600"
      >
        削除
      </button>
      <button onClick={onCancel} className={confirmCancelBtn}>
        キャンセル
      </button>
    </div>
  )
}
