import { useState } from 'react'
import { useAccount, useSwitchChain, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { Check, Loader2, Tag, X } from 'lucide-react'
import { toast } from 'sonner'
import { useChain } from '@/hooks/useChain'
import { MAX_LABEL_BYTES, MAX_LABEL_CHARS } from '@/hooks/useRecipientLabels'
import { cleanName, nameBytes } from '@/hooks/useSplitName'
import { getRecipientLabel } from '@/hooks/useSplitTitle'
import { formatAddress, parseOnchainError } from '@/utils'

/**
 * Lets a split's creator add, change or clear every recipient's name/tag in one on-chain transaction.
 * Tags saved in this browser by an older version are offered as the starting text.
 */
export function RecipientTagsEditor({
  splitId, addrs, labelFor, onClose,
}: {
  splitId: bigint
  addrs: string[]
  labelFor: (addr: string) => string
  onClose: () => void
}) {
  const chain = useChain()
  const queryClient = useQueryClient()
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== chain.id

  const [drafts, setDrafts] = useState<Record<string, string>>(() =>
    Object.fromEntries(addrs.map(a => [a.toLowerCase(), labelFor(a) || getRecipientLabel(chain.id, splitId, a)])),
  )

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: confirming } = useWaitForTransactionReceipt({ hash, query: { enabled: !!hash } })
  const busy = isPending || confirming

  const tooLong = addrs.some(a => nameBytes((drafts[a.toLowerCase()] ?? '').trim()) > MAX_LABEL_BYTES)

  const save = () => {
    if (!chain.labels) return
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (tooLong) return
    writeContract(
      {
        address: chain.labels.address, abi: chain.labels.abi, functionName: 'setLabels', chainId: chain.id,
        args: [splitId, addrs as `0x${string}`[], addrs.map(a => (drafts[a.toLowerCase()] ?? '').trim())],
      },
      {
        onSuccess: () => {
          toast.success('Tags saved on-chain')
          setTimeout(() => void queryClient.invalidateQueries(), 2500)
          onClose()
        },
        onError: e => toast.error(parseOnchainError(e)),
      },
    )
  }

  return (
    <div className="mb-5 rounded-2xl p-4" style={{ background: 'rgba(245,200,66,0.04)', border: '1px solid rgba(245,200,66,0.16)' }}>
      <div className="mb-3 flex items-center justify-between">
        <span className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.08em' }}>
          <Tag className="size-3.5" style={{ color: 'var(--accent)' }} /> Recipient tags
        </span>
        <button onClick={onClose} disabled={busy} aria-label="Close" className="flex size-7 items-center justify-center rounded-lg disabled:opacity-40" style={{ color: 'var(--muted)' }}>
          <X className="size-4" />
        </button>
      </div>

      <div className="space-y-3">
        {addrs.map(a => (
          <div key={a}>
            <p className="mono mb-1 text-xs" style={{ color: 'var(--subtle)' }}>{formatAddress(a)}</p>
            <input
              value={drafts[a.toLowerCase()] ?? ''}
              onChange={e => setDrafts(d => ({ ...d, [a.toLowerCase()]: cleanName(e.target.value).slice(0, MAX_LABEL_CHARS) }))}
              placeholder="Name or tag (optional)"
              disabled={busy}
              className="display w-full rounded-xl px-3.5 py-2.5 text-sm font-semibold outline-none transition-all placeholder:font-normal placeholder:opacity-30 disabled:opacity-60"
              style={{ background: 'rgba(255,255,255,0.04)', color: '#F2CC66', boxShadow: '0 0 0 1px rgba(245,200,66,0.18)' }}
              onFocus={e => (e.currentTarget.style.boxShadow = '0 0 0 1.5px rgba(245,200,66,0.55)')}
              onBlur={e => (e.currentTarget.style.boxShadow = '0 0 0 1px rgba(245,200,66,0.18)')}
            />
          </div>
        ))}
      </div>

      <button
        onClick={save}
        disabled={busy || tooLong}
        className="mt-4 flex w-full items-center justify-center gap-2 rounded-2xl py-3 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: 'var(--accent)', color: '#0c0c0c', boxShadow: '0 4px 24px rgba(245,200,66,0.22)' }}
      >
        {busy ? <><Loader2 className="size-4 animate-spin" />{isPending ? 'Confirm in wallet…' : 'Saving on-chain…'}</>
          : isWrongChain ? `Switch to ${chain.label}` : <><Check className="size-4" />Save tags on-chain</>}
      </button>
    </div>
  )
}
