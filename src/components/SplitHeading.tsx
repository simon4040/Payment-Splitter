import { useState } from 'react'
import { useAccount, useReadContract, useSwitchChain, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { Check, Loader2, Pencil, X } from 'lucide-react'
import { toast } from 'sonner'
import { useChain } from '@/hooks/useChain'
import { MAX_NAME_BYTES, cleanName, nameBytes, useSplitName } from '@/hooks/useSplitName'
import { getSplitTitle } from '@/hooks/useSplitTitle'
import { parseOnchainError } from '@/utils'

/**
 * The split's name, large and gold, read from the blockchain. The creator can name or rename the split
 * (an on-chain transaction); splits without a name show "Split #ID".
 */
export function SplitHeading({ splitId }: { splitId: bigint }) {
  const chain = useChain()
  const queryClient = useQueryClient()
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const { name, loading } = useSplitName(splitId)

  const { data } = useReadContract({
    address: chain.factory.address, abi: chain.factory.abi,
    functionName: 'getSplit', args: [splitId], chainId: chain.id,
  })
  const creator = (data as [string, bigint, bigint, bigint] | undefined)?.[0]
  const isCreator = !!address && !!creator && creator.toLowerCase() === address.toLowerCase()
  const isWrongChain = isConnected && chainId !== chain.id

  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState('')

  const { writeContract, data: hash, isPending, reset } = useWriteContract()
  const { isLoading: confirming } = useWaitForTransactionReceipt({ hash, query: { enabled: !!hash } })
  const busy = isPending || confirming

  const startEdit = () => {
    // A name saved in this browser by an older version is offered as the starting point.
    setDraft(name || getSplitTitle(chain.id, splitId))
    setEditing(true)
  }

  const trimmed = draft.trim()
  const valid = trimmed.length > 0 && nameBytes(trimmed) <= MAX_NAME_BYTES && trimmed !== name

  const save = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (!valid) return
    writeContract(
      { address: chain.names.address, abi: chain.names.abi, functionName: 'setName', args: [splitId, trimmed], chainId: chain.id },
      {
        onSuccess: () => {
          // The name is stored once the transaction confirms; refresh reads a moment later.
          setTimeout(() => void queryClient.invalidateQueries(), 2500)
          toast.success('Name saved on-chain')
          reset()
          setEditing(false)
        },
        onError: e => toast.error(parseOnchainError(e)),
      },
    )
  }

  const shown = name || `Split #${splitId.toString()}`

  return (
    <div className="px-1">
      {editing ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <input
              autoFocus
              value={draft}
              onChange={e => setDraft(cleanName(e.target.value))}
              onKeyDown={e => { if (e.key === 'Enter') save(); if (e.key === 'Escape') setEditing(false) }}
              placeholder="Split name"
              disabled={busy}
              className="display min-w-0 flex-1 rounded-2xl px-4 py-3 text-lg font-semibold outline-none disabled:opacity-60"
              style={{ background: 'rgba(245,200,66,0.04)', color: '#F2CC66', boxShadow: '0 0 0 1.5px rgba(245,200,66,0.45)', letterSpacing: '-0.02em' }}
            />
            <button
              onClick={save}
              disabled={(!valid && !isWrongChain) || busy}
              aria-label="Save name"
              className="flex size-11 shrink-0 items-center justify-center rounded-2xl transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-40"
              style={{ background: 'var(--accent)', color: '#0c0c0c' }}
            >
              {busy ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
            </button>
            <button
              onClick={() => setEditing(false)}
              disabled={busy}
              aria-label="Cancel"
              className="flex size-11 shrink-0 items-center justify-center rounded-2xl transition-all active:scale-95 disabled:opacity-40"
              style={{ background: 'rgba(255,255,255,0.06)', color: 'var(--muted)' }}
            >
              <X className="size-4" />
            </button>
          </div>
          <p className="text-xs tabular-nums" style={{ color: nameBytes(draft) > MAX_NAME_BYTES ? 'var(--danger)' : 'var(--subtle)' }}>
            {isPending ? 'Confirm in your wallet…' : confirming ? 'Saving on-chain…' : `${nameBytes(draft)}/${MAX_NAME_BYTES} · saved on-chain`}
          </p>
        </div>
      ) : (
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2
              className="display truncate text-2xl font-bold leading-tight"
              style={{ color: name ? '#F2CC66' : 'var(--ink)', letterSpacing: '-0.03em', opacity: loading && !name ? 0.5 : 1 }}
              title={shown}
            >
              {shown}
            </h2>
            <p className="mt-1 flex items-center gap-2 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
              <span className="rounded-md px-1.5 py-0.5 font-semibold" style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)' }}>
                #{splitId.toString()}
              </span>
              {chain.label}
            </p>
          </div>
          {isCreator && (
            <button
              onClick={startEdit}
              className="flex shrink-0 items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-all active:scale-95"
              style={{ background: 'rgba(255,255,255,0.05)', color: 'var(--ink-2)', boxShadow: '0 0 0 1px rgba(245,200,66,0.18)' }}
            >
              <Pencil className="size-3" />{name ? 'Edit' : 'Add name'}
            </button>
          )}
        </div>
      )}
    </div>
  )
}
