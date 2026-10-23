import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { AnimatePresence, motion } from 'framer-motion'
import { X, Plus, Trash2, Loader2, GitBranch } from 'lucide-react'
import { toast } from 'sonner'
import { SPLIT_FACTORY, ARC_MAINNET_ID } from '@/contract'
import { parseOnchainError } from '@/utils'
import { setSplitTitle, setRecipientLabel } from '@/hooks/useSplitTitle'

interface Props {
  open: boolean
  onClose: () => void
  onCreated: (splitId: bigint) => void
}

interface Row { addr: string; pct: string; label: string }

const DEFAULT_ROWS: Row[] = [
  { addr: '', pct: '', label: '' },
  { addr: '', pct: '', label: '' },
]
const spring = { type: 'spring', damping: 32, stiffness: 340 }

const inputBase: React.CSSProperties = {
  background: 'rgba(255,255,255,0.05)',
  color: 'var(--ink)',
  boxShadow: '0 0 0 1px rgba(255,255,255,0.09)',
}
const inputFocus = '0 0 0 1.5px rgba(245,200,66,0.45)'
const inputBlur  = '0 0 0 1px rgba(255,255,255,0.09)'

export function CreateSplitSheet({ open, onClose, onCreated }: Props) {
  const [title, setTitle] = useState('')
  const [rows, setRows] = useState<Row[]>(DEFAULT_ROWS)
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== ARC_MAINNET_ID

  const totalBps = rows.reduce((s, r) => {
    const p = parseFloat(r.pct)
    return s + (isNaN(p) ? 0 : Math.round(p * 100))
  }, 0)
  const remaining = 10000 - totalBps
  const isValid =
    rows.length >= 1 && rows.length <= 20 &&
    rows.every(r => /^0x[0-9a-fA-F]{40}$/.test(r.addr.trim())) &&
    rows.every(r => parseFloat(r.pct) > 0) &&
    totalBps === 10000

  const setRow = (i: number, f: keyof Row, v: string) =>
    setRows(p => p.map((r, idx) => idx === i ? { ...r, [f]: v } : r))

  const { writeContract, isPending, reset: resetWrite } = useWriteContract()
  const [pendingHash, setPendingHash] = useState<`0x${string}` | undefined>()
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: pendingHash, query: { enabled: !!pendingHash },
  })

  const handleCreate = () => {
    if (isWrongChain) { switchChain({ chainId: ARC_MAINNET_ID }); return }
    if (!isValid) return
    const addrs = rows.map(r => r.addr.trim() as `0x${string}`)
    const bpsArr = rows.map(r => Math.round(parseFloat(r.pct) * 100))
    writeContract(
      { address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi, functionName: 'createSplit', args: [addrs, bpsArr], chainId: ARC_MAINNET_ID },
      {
        onSuccess: (hash) => setPendingHash(hash),
        onError: (err) => toast.error(parseOnchainError(err)),
      }
    )
  }

  const { data: receipt } = useWaitForTransactionReceipt({ hash: pendingHash, query: { enabled: !!pendingHash } })

  if (receipt && pendingHash) {
    const log = receipt.logs.find(l => l.address.toLowerCase() === SPLIT_FACTORY.address.toLowerCase())
    if (log && log.topics[1]) {
      const splitId = BigInt(log.topics[1])
      setSplitTitle(splitId, title)
      // Persist any recipient labels
      rows.forEach(r => {
        if (r.label.trim() && /^0x[0-9a-fA-F]{40}$/.test(r.addr.trim())) {
          setRecipientLabel(splitId, r.addr.trim(), r.label)
        }
      })
      resetWrite()
      setPendingHash(undefined)
      setRows(DEFAULT_ROWS)
      setTitle('')
      onCreated(splitId)
      onClose()
    }
  }

  const isBusy = isPending || isConfirming

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <div className="absolute inset-0" style={{ background: 'rgba(4,4,4,0.82)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)' }} />

          <motion.div
            className="relative w-full max-w-md overflow-hidden sm:rounded-3xl rounded-t-3xl"
            style={{
              background: '#161616',
              border: '1px solid rgba(245,200,66,0.14)',
              boxShadow: '0 32px 80px rgba(0,0,0,0.70), 0 0 0 1px rgba(245,200,66,0.06)',
              maxHeight: '90dvh',
              overflowY: 'auto',
            }}
            initial={{ y: '100%' }} animate={{ y: 0 }} exit={{ y: '100%' }}
            transition={spring}
            onClick={e => e.stopPropagation()}
          >
            <div className="flex justify-center pt-3 sm:hidden">
              <div className="h-1 w-9 rounded-full" style={{ background: 'rgba(255,255,255,0.14)' }} />
            </div>

            <div className="px-6 pt-5 pb-7">
              {/* Header */}
              <div className="flex items-center justify-between mb-7">
                <div className="flex items-center gap-3">
                  <div className="flex size-8 items-center justify-center rounded-xl"
                    style={{ background: 'rgba(245,200,66,0.10)', border: '1px solid rgba(245,200,66,0.20)' }}>
                    <GitBranch className="size-4" style={{ color: 'var(--accent)' }} />
                  </div>
                  <div>
                    <h2 className="display text-base font-semibold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>New Split</h2>
                    <p className="text-xs" style={{ color: 'var(--muted)' }}>Configure recipients and shares</p>
                  </div>
                </div>
                <button
                  onClick={onClose}
                  className="flex size-8 items-center justify-center rounded-full transition-colors"
                  style={{ color: 'var(--muted)' }}
                  onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.07)')}
                  onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                >
                  <X className="size-4" />
                </button>
              </div>

              {/* Title (optional) */}
              <div className="mb-5">
                <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--muted)' }}>
                  Title <span style={{ color: 'var(--subtle)' }}>— optional</span>
                </label>
                <input
                  value={title}
                  onChange={e => setTitle(e.target.value)}
                  placeholder="e.g. Team payout – October"
                  maxLength={60}
                  className="w-full rounded-xl px-3.5 py-2.5 text-sm outline-none transition-all placeholder:opacity-30"
                  style={inputBase}
                  onFocus={e => (e.currentTarget.style.boxShadow = inputFocus)}
                  onBlur={e => (e.currentTarget.style.boxShadow = inputBlur)}
                />
              </div>

              {/* Recipient rows */}
              <div className="space-y-3 mb-4">
                {rows.map((row, i) => (
                  <div key={i} className="rounded-2xl p-3" style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.06)' }}>
                    <div className="flex items-center gap-2 mb-2">
                      {/* Index dot */}
                      <div className="shrink-0 size-5 rounded-full flex items-center justify-center text-xs font-semibold tabular-nums"
                        style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--muted)', fontSize: '0.65rem', minWidth: '1.25rem' }}>
                        {i + 1}
                      </div>
                      {/* Address */}
                      <input
                        value={row.addr}
                        onChange={e => setRow(i, 'addr', e.target.value)}
                        placeholder="0x… wallet address"
                        spellCheck={false}
                        className="mono flex-1 min-w-0 rounded-xl px-3 py-2 text-xs outline-none transition-all placeholder:opacity-30"
                        style={inputBase}
                        onFocus={e => (e.currentTarget.style.boxShadow = inputFocus)}
                        onBlur={e => (e.currentTarget.style.boxShadow = inputBlur)}
                      />
                      {/* Percentage */}
                      <div className="relative w-[4.5rem] shrink-0">
                        <input
                          value={row.pct}
                          onChange={e => {
                            const v = e.target.value.replace(/[^0-9.]/g, '')
                            if (v === '' || /^\d*\.?\d*$/.test(v)) setRow(i, 'pct', v)
                          }}
                          placeholder="0"
                          inputMode="decimal"
                          className="w-full rounded-xl px-3 py-2 text-xs text-right tabular-nums outline-none transition-all placeholder:opacity-30 pr-5"
                          style={inputBase}
                          onFocus={e => (e.currentTarget.style.boxShadow = inputFocus)}
                          onBlur={e => (e.currentTarget.style.boxShadow = inputBlur)}
                        />
                        <span className="absolute right-2.5 top-1/2 -translate-y-1/2 text-xs pointer-events-none" style={{ color: 'var(--muted)' }}>%</span>
                      </div>
                      {/* Delete */}
                      {rows.length > 1 && (
                        <button onClick={() => setRows(r => r.filter((_, idx) => idx !== i))}
                          className="shrink-0 transition-opacity hover:opacity-60" style={{ color: 'var(--muted)' }}>
                          <Trash2 className="size-3.5" />
                        </button>
                      )}
                    </div>

                    {/* Label — optional, always visible but clearly secondary */}
                    <div className="pl-7">
                      <input
                        value={row.label}
                        onChange={e => setRow(i, 'label', e.target.value)}
                        placeholder="Label / username — optional"
                        maxLength={40}
                        className="w-full rounded-lg px-2.5 py-1.5 text-xs outline-none transition-all placeholder:opacity-25"
                        style={{
                          background: 'rgba(255,255,255,0.03)',
                          color: 'var(--ink-2)',
                          boxShadow: '0 0 0 1px rgba(255,255,255,0.06)',
                        }}
                        onFocus={e => (e.currentTarget.style.boxShadow = inputFocus)}
                        onBlur={e => (e.currentTarget.style.boxShadow = '0 0 0 1px rgba(255,255,255,0.06)')}
                      />
                    </div>
                  </div>
                ))}
              </div>

              {/* Add row + total */}
              <div className="flex items-center justify-between mb-6">
                {rows.length < 20 ? (
                  <button onClick={() => setRows(r => [...r, { addr: '', pct: '', label: '' }])}
                    className="flex items-center gap-1.5 text-xs font-medium transition-opacity hover:opacity-70"
                    style={{ color: 'var(--accent)' }}>
                    <Plus className="size-3.5" /> Add recipient
                  </button>
                ) : (
                  <span className="text-xs" style={{ color: 'var(--muted)' }}>Max 20</span>
                )}
                <span className="text-xs font-semibold tabular-nums" style={{
                  color: totalBps === 10000 ? 'var(--success)' : remaining > 0 ? 'var(--accent)' : 'var(--danger)',
                }}>
                  {totalBps === 10000 ? '100% ✓' : remaining > 0 ? `${(remaining / 100).toFixed(2)}% left` : `${(Math.abs(remaining) / 100).toFixed(2)}% over`}
                </span>
              </div>

              {/* CTA */}
              <button
                disabled={(!isValid && !isWrongChain) || isBusy}
                onClick={handleCreate}
                className="w-full rounded-2xl py-3.5 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed"
                style={{
                  background: isValid || isWrongChain ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
                  color: isValid || isWrongChain ? '#0c0c0c' : 'var(--muted)',
                  boxShadow: isValid && !isBusy ? '0 0 28px rgba(245,200,66,0.24)' : 'none',
                  opacity: ((!isValid && !isWrongChain) || isBusy) ? 0.4 : 1,
                }}
              >
                {isWrongChain ? 'Switch Network' : isBusy ? (
                  <span className="flex items-center justify-center gap-2">
                    <Loader2 className="size-4 animate-spin" />
                    {isPending ? 'Confirm in wallet…' : 'Creating split…'}
                  </span>
                ) : 'Create Split'}
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
