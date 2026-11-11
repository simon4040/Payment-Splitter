import { useCallback, useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { AnimatePresence, motion } from 'framer-motion'
import { X, Plus, Trash2, Loader2, GitBranch } from 'lucide-react'
import { toast } from 'sonner'
import { useChain } from '@/hooks/useChain'
import { parseOnchainError } from '@/utils'
import { setRecipientLabel } from '@/hooks/useSplitTitle'
import { MAX_NAME_BYTES, cleanName, nameBytes } from '@/hooks/useSplitName'
import { MAX_LABEL_BYTES } from '@/hooks/useRecipientLabels'

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
  const chain = useChain()
  const queryClient = useQueryClient()
  const [name, setName] = useState('')
  const [rows, setRows] = useState<Row[]>(DEFAULT_ROWS)
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== chain.id

  const totalBps = rows.reduce((s, r) => {
    const p = parseFloat(r.pct)
    return s + (isNaN(p) ? 0 : Math.round(p * 100))
  }, 0)
  const remaining = 10000 - totalBps
  const trimmedName = name.trim()
  const nameOk = trimmedName.length > 0 && nameBytes(trimmedName) <= MAX_NAME_BYTES
  const isValid =
    nameOk &&
    rows.length >= 1 && rows.length <= 20 &&
    rows.every(r => /^0x[0-9a-fA-F]{40}$/.test(r.addr.trim())) &&
    rows.every(r => parseFloat(r.pct) > 0) &&
    rows.every(r => nameBytes(r.label.trim()) <= MAX_LABEL_BYTES) &&
    totalBps === 10000

  const setRow = (i: number, f: keyof Row, v: string) =>
    setRows(p => p.map((r, idx) => idx === i ? { ...r, [f]: v } : r))

  // Step 1: create the split. Step 2: store its name on-chain.
  const createW = useWriteContract()
  const createRcpt = useWaitForTransactionReceipt({ hash: createW.data, query: { enabled: !!createW.data } })
  const nameW = useWriteContract()
  const nameRcpt = useWaitForTransactionReceipt({ hash: nameW.data, query: { enabled: !!nameW.data } })
  const labelsW = useWriteContract()
  const labelsRcpt = useWaitForTransactionReceipt({ hash: labelsW.data, query: { enabled: !!labelsW.data } })

  // Recipient tags go on-chain too (one extra confirmation), when a registry exists on this chain.
  const labeled = rows.filter(r => r.label.trim() && /^0x[0-9a-fA-F]{40}$/.test(r.addr.trim()))
  const saveTagsOnChain = !!chain.labels && labeled.length > 0
  const totalSteps = saveTagsOnChain ? 3 : 2

  const createdId = useRef<bigint | null>(null)
  const handledCreate = useRef<string | null>(null)
  const handledName = useRef<string | null>(null)
  const handledLabels = useRef<string | null>(null)

  const finish = useCallback((id: bigint) => {
    void queryClient.invalidateQueries()
    createW.reset()
    nameW.reset()
    labelsW.reset()
    createdId.current = null
    setRows(DEFAULT_ROWS)
    setName('')
    onCreated(id)
    onClose()
  }, [queryClient, createW, nameW, labelsW, onCreated, onClose])

  // After the name step: save recipient tags on-chain, or finish.
  const afterName = useCallback((id: bigint) => {
    if (!chain.labels || labeled.length === 0) { finish(id); return }
    labelsW.writeContract(
      {
        address: chain.labels.address, abi: chain.labels.abi, functionName: 'setLabels', chainId: chain.id,
        args: [id, labeled.map(r => r.addr.trim() as `0x${string}`), labeled.map(r => r.label.trim())],
      },
      {
        onError: () => {
          toast.message('Split created. Add recipient tags from the split page.')
          finish(id)
        },
      },
    )
  }, [chain, labeled, labelsW, finish])

  // Split created: ask the wallet to store the name on-chain.
  useEffect(() => {
    const hash = createW.data
    const receipt = createRcpt.data
    if (!hash || !receipt || handledCreate.current === hash) return
    handledCreate.current = hash
    const log = receipt.logs.find(l => l.address.toLowerCase() === chain.factory.address.toLowerCase())
    if (!log?.topics[1]) { toast.error('Split created, but its id could not be read. Check Your Splits.'); createW.reset(); return }
    const id = BigInt(log.topics[1])
    createdId.current = id
    // Without an on-chain tag registry, tags stay in this browser as before.
    if (!chain.labels) {
      rows.forEach(r => {
        if (r.label.trim() && /^0x[0-9a-fA-F]{40}$/.test(r.addr.trim())) {
          setRecipientLabel(chain.id, id, r.addr.trim(), r.label)
        }
      })
    }
    nameW.writeContract(
      { address: chain.names.address, abi: chain.names.abi, functionName: 'setName', args: [id, trimmedName], chainId: chain.id },
      {
        onError: () => {
          toast.message('Split created. Add its name from the split page.')
          afterName(id)
        },
      },
    )
  }, [createW, createRcpt.data, chain, rows, trimmedName, nameW, afterName])

  // Name stored: continue to tags (or finish).
  useEffect(() => {
    const hash = nameW.data
    if (!hash || handledName.current === hash || createdId.current === null) return
    if (nameRcpt.isSuccess) {
      handledName.current = hash
      afterName(createdId.current)
    } else if (nameRcpt.isError) {
      handledName.current = hash
      toast.message('Split created. Add its name from the split page.')
      afterName(createdId.current)
    }
  }, [nameW.data, nameRcpt.isSuccess, nameRcpt.isError, afterName])

  // Tags stored: done.
  useEffect(() => {
    const hash = labelsW.data
    if (!hash || handledLabels.current === hash || createdId.current === null) return
    if (labelsRcpt.isSuccess) {
      handledLabels.current = hash
      toast.success('Split created')
      finish(createdId.current)
    } else if (labelsRcpt.isError) {
      handledLabels.current = hash
      toast.message('Split created. Add recipient tags from the split page.')
      finish(createdId.current)
    }
  }, [labelsW.data, labelsRcpt.isSuccess, labelsRcpt.isError, finish])

  const handleCreate = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (!isValid) return
    const addrs = rows.map(r => r.addr.trim() as `0x${string}`)
    const bpsArr = rows.map(r => Math.round(parseFloat(r.pct) * 100))
    createW.writeContract(
      { address: chain.factory.address, abi: chain.factory.abi, functionName: 'createSplit', args: [addrs, bpsArr], chainId: chain.id },
      { onError: (err) => toast.error(parseOnchainError(err)) },
    )
  }

  const isNaming = nameW.isPending || nameRcpt.isLoading || (createRcpt.isSuccess && !nameW.data && !nameW.isError)
  const isTagging = saveTagsOnChain && (labelsW.isPending || labelsRcpt.isLoading || (nameRcpt.isSuccess && !labelsW.data && !labelsW.isError))
  const isBusy = createW.isPending || createRcpt.isLoading || isNaming || isTagging
  const stepLabel = createW.isPending ? 'Confirm in wallet…'
    : createRcpt.isLoading ? 'Creating split…'
    : isTagging ? (labelsW.isPending ? `Confirm tags in wallet… (3 of ${totalSteps})` : `Saving tags on-chain… (3 of ${totalSteps})`)
    : nameW.isPending ? `Confirm name in wallet… (2 of ${totalSteps})`
    : `Saving name on-chain… (2 of ${totalSteps})`

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

              {/* Name (required, stored on-chain) */}
              <div className="mb-6">
                <label htmlFor="split-name" className="mb-2 flex items-baseline justify-between text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
                  <span>Split name <span style={{ color: 'var(--accent)' }}>*</span></span>
                  <span className="font-medium normal-case tabular-nums" style={{ color: nameBytes(name) > MAX_NAME_BYTES ? 'var(--danger)' : 'var(--subtle)', letterSpacing: 0 }}>
                    {nameBytes(name)}/{MAX_NAME_BYTES}
                  </span>
                </label>
                <input
                  id="split-name"
                  value={name}
                  onChange={e => setName(cleanName(e.target.value))}
                  placeholder="e.g. Team payout, October"
                  autoComplete="off"
                  className="display w-full rounded-2xl px-4 py-3.5 text-lg font-semibold outline-none transition-all placeholder:font-normal placeholder:opacity-30"
                  style={{
                    background: 'rgba(245,200,66,0.04)',
                    color: '#F2CC66',
                    letterSpacing: '-0.02em',
                    boxShadow: '0 0 0 1px rgba(245,200,66,0.22)',
                  }}
                  onFocus={e => (e.currentTarget.style.boxShadow = '0 0 0 1.5px rgba(245,200,66,0.60), 0 0 24px rgba(245,200,66,0.10)')}
                  onBlur={e => (e.currentTarget.style.boxShadow = '0 0 0 1px rgba(245,200,66,0.22)')}
                />
                <p className="mt-2 text-xs" style={{ color: 'var(--subtle)' }}>
                  Saved on-chain, so it shows on any device. Your wallet asks to confirm the name{saveTagsOnChain ? ' and tags' : ''} right after the split is created.
                </p>
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
                    {stepLabel}
                  </span>
                ) : !nameOk ? 'Enter a split name' : 'Create Split'}
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
