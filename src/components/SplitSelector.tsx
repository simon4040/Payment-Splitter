/**
 * Shows a list of splits created by the connected wallet (newest first),
 * plus a "Jump to any split ID" input.
 */
import { useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { ChevronRight, Hash, Trash2, X, Check } from 'lucide-react'
import { SPLIT_FACTORY, ARC_MAINNET_ID } from '@/contract'
import { useSplitIds } from '@/hooks/useSplitIds'
import { getSplitTitle, splitLabel, hideSplit, filterVisible } from '@/hooks/useSplitTitle'
import { formatUsdc } from '@/utils'

interface Props {
  selected: bigint | null
  onSelect: (id: bigint) => void
  onDeselect?: () => void
}

function SplitRow({
  splitId, selected, onSelect, onHide,
}: {
  splitId: bigint
  selected: bigint | null
  onSelect: (id: bigint) => void
  onHide: (id: bigint) => void
}) {
  const isSelected = selected === splitId
  const [confirming, setConfirming] = useState(false)

  const { data } = useReadContract({
    address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi,
    functionName: 'getSplit', args: [splitId], chainId: ARC_MAINNET_ID,
    query: { refetchInterval: 10000 },
  })
  const [, balance, , recipientCount] = (data as [string, bigint, bigint, bigint] | undefined) ?? ['', 0n, 0n, 0n]
  const title = getSplitTitle(splitId)
  const label = splitLabel(splitId)

  const handleDeleteClick = (e: React.MouseEvent) => { e.stopPropagation(); setConfirming(true) }
  const handleConfirm = (e: React.MouseEvent) => { e.stopPropagation(); onHide(splitId) }
  const handleCancel = (e: React.MouseEvent) => { e.stopPropagation(); setConfirming(false) }

  return (
    <div
      className="flex items-center gap-2 rounded-2xl transition-all"
      style={{
        background: isSelected ? 'rgba(245,200,66,0.08)' : 'rgba(255,255,255,0.03)',
        border: `1px solid ${isSelected ? 'rgba(245,200,66,0.28)' : 'rgba(255,255,255,0.08)'}`,
        boxShadow: isSelected ? '0 0 0 0.5px rgba(245,200,66,0.10)' : 'none',
      }}
    >
      <button
        onClick={() => onSelect(splitId)}
        className="flex items-center gap-3 flex-1 min-w-0 px-4 py-3.5 text-left"
      >
        <div className="size-8 rounded-xl flex items-center justify-center shrink-0"
          style={{ background: isSelected ? 'rgba(245,200,66,0.16)' : 'rgba(255,255,255,0.06)' }}>
          <span className="display text-sm font-bold tabular-nums"
            style={{ color: isSelected ? 'var(--accent)' : 'var(--muted)' }}>
            {splitId.toString()}
          </span>
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold truncate"
            style={{ color: title ? '#E8B84B' : isSelected ? 'var(--ink)' : 'var(--ink-2)' }}>
            {label}
          </p>
          <p className="text-xs tabular-nums mt-0.5" style={{ color: 'var(--muted)' }}>
            {title ? <span className="mono" style={{ opacity: 0.6 }}>#{splitId.toString()} · </span> : null}
            {formatUsdc(balance)} USDC · {recipientCount.toString()} recipients
          </p>
        </div>
        <ChevronRight className="size-4 shrink-0"
          style={{ color: isSelected ? 'var(--accent)' : 'var(--muted)', opacity: isSelected ? 1 : 0.5 }} />
      </button>

      <div className="shrink-0 pr-3 flex items-center gap-1">
        {confirming ? (
          <>
            <button onClick={handleConfirm} title="Confirm remove"
              className="flex items-center justify-center size-7 rounded-lg transition-all"
              style={{ background: 'rgba(248,113,113,0.12)', color: '#f87171' }}>
              <Check className="size-3.5" />
            </button>
            <button onClick={handleCancel} title="Cancel"
              className="flex items-center justify-center size-7 rounded-lg transition-all"
              style={{ background: 'rgba(255,255,255,0.06)', color: 'var(--muted)' }}>
              <X className="size-3.5" />
            </button>
          </>
        ) : (
          <button
            onClick={handleDeleteClick} title="Remove from list"
            className="flex items-center justify-center size-7 rounded-lg transition-all"
            style={{ color: 'var(--subtle)' }}
            onMouseEnter={e => {
              e.currentTarget.style.background = 'rgba(248,113,113,0.10)'
              e.currentTarget.style.color = '#f87171'
            }}
            onMouseLeave={e => {
              e.currentTarget.style.background = 'transparent'
              e.currentTarget.style.color = 'var(--subtle)'
            }}
          >
            <Trash2 className="size-3.5" />
          </button>
        )}
      </div>
    </div>
  )
}

export function SplitSelector({ selected, onSelect, onDeselect }: Props) {
  const { address } = useAccount()
  const { ids: rawIds, loading } = useSplitIds(address)
  const [jumpId, setJumpId] = useState('')
  const [hiddenIds, setHiddenIds] = useState<Set<string>>(() => new Set())

  const { data: splitCount } = useReadContract({
    address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi,
    functionName: 'splitCount', chainId: ARC_MAINNET_ID,
    query: { refetchInterval: 8000 },
  })
  const count = splitCount as bigint | undefined

  const visibleIds = filterVisible(rawIds)
    .filter(id => !hiddenIds.has(id.toString()))
    .slice()
    .reverse()

  const handleHide = (id: bigint) => {
    hideSplit(id)
    setHiddenIds(prev => new Set([...prev, id.toString()]))
    if (selected === id) onDeselect?.()
  }

  const handleJump = () => {
    const n = BigInt(parseInt(jumpId, 10))
    if (n > 0n && count !== undefined && n <= count) { onSelect(n); setJumpId('') }
  }

  if (!address) return null

  return (
    <div className="rounded-3xl p-5" style={{
      background: 'rgba(255,255,255,0.03)',
      border: '1px solid rgba(245,200,66,0.10)',
    }}>
      <p className="text-xs font-semibold uppercase tracking-widest mb-4"
        style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
        Your Splits
      </p>

      {loading ? (
        <div className="space-y-2.5">
          {[1, 2].map(i => (
            <div key={i} className="h-[3.25rem] rounded-2xl animate-pulse"
              style={{ background: 'rgba(255,255,255,0.06)' }} />
          ))}
        </div>
      ) : visibleIds.length === 0 ? (
        <p className="text-sm py-4 text-center" style={{ color: 'var(--muted)' }}>
          No splits created yet
        </p>
      ) : (
        <div className="space-y-2">
          {visibleIds.map(id => (
            <SplitRow key={id.toString()} splitId={id} selected={selected} onSelect={onSelect} onHide={handleHide} />
          ))}
        </div>
      )}

      {count !== undefined && count > 0n && (
        <div className="mt-4 pt-4 border-t" style={{ borderColor: 'rgba(245,200,66,0.10)' }}>
          <p className="text-xs mb-2.5" style={{ color: 'var(--muted)' }}>
            Jump to any split{' '}
            <span style={{ color: 'var(--subtle)' }}>(1 – {count.toString()} exist)</span>
          </p>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Hash className="absolute left-3 top-1/2 -translate-y-1/2 size-3.5" style={{ color: 'var(--muted)' }} />
              <input
                type="number" min="1" value={jumpId}
                onChange={e => setJumpId(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleJump()}
                placeholder="Split ID"
                className="w-full rounded-xl pl-8 pr-3 py-2.5 text-sm tabular-nums outline-none"
                style={{
                  background: 'rgba(255,255,255,0.05)',
                  color: 'var(--ink-2)',
                  boxShadow: '0 0 0 1px rgba(245,200,66,0.12)',
                }}
              />
            </div>
            <button
              disabled={!jumpId}
              onClick={handleJump}
              className="rounded-xl px-4 py-2.5 text-sm font-semibold disabled:opacity-40 transition-opacity hover:opacity-80"
              style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)' }}
            >
              View
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
