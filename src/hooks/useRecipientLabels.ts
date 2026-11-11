/**
 * Recipient names/tags live on-chain (RecipientLabels), so they show on any device and survive
 * clearing browser data. A recipient without a tag returns "" and the UI shows just the address.
 * Until the registry exists on a chain, tags saved in this browser are shown instead.
 */
import { useReadContract } from 'wagmi'
import { useChain } from '@/hooks/useChain'
import { getRecipientLabel } from '@/hooks/useSplitTitle'
import { LABELS_ABI } from '@/contract'

export const MAX_LABEL_BYTES = 64
export const MAX_LABEL_CHARS = 40

export function useRecipientLabels(splitId: bigint, addrs: string[]) {
  const chain = useChain()
  const registry = chain.labels
  const q = useReadContract({
    address: registry?.address ?? '0x0000000000000000000000000000000000000001',
    abi: LABELS_ABI,
    functionName: 'labelsOf',
    args: [splitId, addrs as `0x${string}`[]],
    chainId: chain.id,
    query: { enabled: !!registry && addrs.length > 0, refetchInterval: 15_000 },
  })
  const list = (q.data as string[] | undefined) ?? []

  /** The tag for a recipient ("" when none). */
  const labelFor = (addr: string): string => {
    if (!registry) return getRecipientLabel(chain.id, splitId, addr)
    const i = addrs.findIndex(a => a.toLowerCase() === addr.toLowerCase())
    return (i >= 0 ? list[i] ?? '' : '').trim()
  }
  return { labelFor, onChain: !!registry, loading: q.isLoading }
}
