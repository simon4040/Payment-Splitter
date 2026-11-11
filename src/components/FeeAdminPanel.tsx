/**
 * Owner-only controls for the protocol fee. Renders nothing unless the connected
 * wallet is the contract owner.
 */
import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { ChevronDown, Loader2, SlidersHorizontal } from 'lucide-react'
import { toast } from 'sonner'
import { useChain } from '@/hooks/useChain'
import { bpsToPercent, formatAddress, parseOnchainError } from '@/utils'
import { useFeeConfig, MAX_FEE_BPS } from '@/hooks/useFeeConfig'

const field: React.CSSProperties = {
  background: 'rgba(255,255,255,0.05)',
  color: 'var(--ink)',
  boxShadow: '0 0 0 1px rgba(255,255,255,0.09)',
}
const focusRing = '0 0 0 1.5px rgba(245,200,66,0.45)'
const idleRing = '0 0 0 1px rgba(255,255,255,0.09)'

/** "0.5" -> 50n. Returns null when not a valid percent with at most 2 decimals. */
function percentToBps(value: string): bigint | null {
  if (!/^\d{1,2}(\.\d{0,2})?$/.test(value.trim())) return null
  const [w, f = ''] = value.trim().split('.')
  return BigInt(w) * 100n + BigInt((f + '00').slice(0, 2))
}

export function FeeAdminPanel() {
  const chain = useChain()
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const { feeBps, feeRecipient, owner, refetch } = useFeeConfig()

  const [open, setOpen] = useState(false)
  const [pct, setPct] = useState('')
  const [recipient, setRecipient] = useState('')

  const feeWrite = useWriteContract()
  const feeReceipt = useWaitForTransactionReceipt({ hash: feeWrite.data, query: { enabled: !!feeWrite.data } })
  const recWrite = useWriteContract()
  const recReceipt = useWaitForTransactionReceipt({ hash: recWrite.data, query: { enabled: !!recWrite.data } })

  const isOwner = !!address && !!owner && address.toLowerCase() === owner.toLowerCase()
  if (!isConnected || !isOwner || feeBps === undefined) return null

  const isWrongChain = chainId !== chain.id
  const newBps = percentToBps(pct)
  const bpsValid = newBps !== null && newBps <= MAX_FEE_BPS
  const bpsChanged = bpsValid && newBps !== BigInt(feeBps)
  const recValid = /^0x[0-9a-fA-F]{40}$/.test(recipient.trim())
  const recChanged = recValid && recipient.trim().toLowerCase() !== feeRecipient?.toLowerCase()
  const feeBusy = feeWrite.isPending || feeReceipt.isLoading
  const recBusy = recWrite.isPending || recReceipt.isLoading

  const submitFee = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (!bpsValid || newBps === null) return
    feeWrite.writeContract({
      address: chain.factory.address, abi: chain.factory.abi, functionName: 'setFeeBps',
      args: [Number(newBps)], chainId: chain.id,
    }, {
      onSuccess: () => { toast.success('Fee updated.'); setPct(''); setTimeout(refetch, 2500) },
      onError: (e) => toast.error(parseOnchainError(e)),
    })
  }

  const submitRecipient = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (!recValid) return
    recWrite.writeContract({
      address: chain.factory.address, abi: chain.factory.abi, functionName: 'setFeeRecipient',
      args: [recipient.trim() as `0x${string}`], chainId: chain.id,
    }, {
      onSuccess: () => { toast.success('Fee recipient updated.'); setRecipient(''); setTimeout(refetch, 2500) },
      onError: (e) => toast.error(parseOnchainError(e)),
    })
  }

  const primaryBtn = (enabled: boolean): React.CSSProperties => ({
    background: enabled ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
    color: enabled ? '#0c0c0c' : 'var(--muted)',
    opacity: enabled ? 1 : 0.5,
  })

  return (
    <div className="rounded-3xl overflow-hidden" style={{
      background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(245,200,66,0.10)',
    }}>
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between px-5 py-4 text-left transition-colors hover:bg-white/[0.03]"
      >
        <div className="flex items-center gap-2.5">
          <SlidersHorizontal className="size-3.5" style={{ color: 'var(--accent)' }} />
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
            Owner · Protocol fee
          </span>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs font-semibold tabular-nums rounded-full px-2 py-0.5"
            style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)' }}>
            {bpsToPercent(BigInt(feeBps))}%
          </span>
          <ChevronDown className="size-4 transition-transform" style={{ color: 'var(--muted)', transform: open ? 'rotate(180deg)' : 'none' }} />
        </div>
      </button>

      {open && (
        <div className="px-5 pb-5 space-y-5">
          {/* Fee percent */}
          <div className="space-y-2">
            <label className="block text-xs font-medium" style={{ color: 'var(--muted)' }}>
              Fee percentage <span style={{ color: 'var(--subtle)' }}>— max {bpsToPercent(MAX_FEE_BPS)}%</span>
            </label>
            <div className="flex gap-2">
              <div className="relative flex-1">
                <input
                  value={pct} inputMode="decimal"
                  onChange={e => setPct(e.target.value.replace(/[^0-9.]/g, ''))}
                  placeholder={bpsToPercent(BigInt(feeBps))}
                  className="w-full rounded-xl pl-3.5 pr-8 py-2.5 text-sm tabular-nums outline-none placeholder:opacity-30"
                  style={field}
                  onFocus={e => (e.currentTarget.style.boxShadow = focusRing)}
                  onBlur={e => (e.currentTarget.style.boxShadow = idleRing)}
                />
                <span className="absolute right-3.5 top-1/2 -translate-y-1/2 text-xs pointer-events-none" style={{ color: 'var(--muted)' }}>%</span>
              </div>
              <button
                disabled={!bpsChanged || feeBusy}
                onClick={submitFee}
                className="rounded-xl px-4 py-2.5 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed flex items-center gap-2"
                style={primaryBtn(bpsChanged && !feeBusy)}
              >
                {feeBusy ? <Loader2 className="size-4 animate-spin" /> : null}
                {feeWrite.isPending ? 'Confirm…' : feeReceipt.isLoading ? 'Updating…' : 'Update'}
              </button>
            </div>
            {pct && !bpsValid && (
              <p className="text-xs" style={{ color: 'var(--danger)' }}>
                Enter a percentage between 0 and {bpsToPercent(MAX_FEE_BPS)}, up to 2 decimals.
              </p>
            )}
          </div>

          {/* Fee recipient */}
          <div className="space-y-2">
            <label className="block text-xs font-medium" style={{ color: 'var(--muted)' }}>
              Fee recipient{feeRecipient ? <span style={{ color: 'var(--subtle)' }}> — now <span className="mono">{formatAddress(feeRecipient)}</span></span> : null}
            </label>
            <div className="flex gap-2">
              <input
                value={recipient} spellCheck={false}
                onChange={e => setRecipient(e.target.value)}
                placeholder="0x… new fee recipient"
                className="mono flex-1 min-w-0 rounded-xl px-3.5 py-2.5 text-xs outline-none placeholder:opacity-30"
                style={field}
                onFocus={e => (e.currentTarget.style.boxShadow = focusRing)}
                onBlur={e => (e.currentTarget.style.boxShadow = idleRing)}
              />
              <button
                disabled={!recChanged || recBusy}
                onClick={submitRecipient}
                className="rounded-xl px-4 py-2.5 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed flex items-center gap-2"
                style={primaryBtn(recChanged && !recBusy)}
              >
                {recBusy ? <Loader2 className="size-4 animate-spin" /> : null}
                {recWrite.isPending ? 'Confirm…' : recReceipt.isLoading ? 'Updating…' : 'Update'}
              </button>
            </div>
            {recipient && !recValid && (
              <p className="text-xs" style={{ color: 'var(--danger)' }}>Enter a valid 0x wallet address.</p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
