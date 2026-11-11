/**
 * Split names live on-chain (SplitNames). These hooks read them from the blockchain, so a name
 * shows up on any device and survives clearing browser data. A split with no name returns "",
 * and the UI falls back to "Split #ID".
 */
import { useReadContract } from 'wagmi'
import { useChain } from '@/hooks/useChain'

export const MAX_NAME_BYTES = 60

/** The text shown for a split: its on-chain name, or "Split #ID" when it has none. */
export function displayName(splitId: bigint, name: string | undefined): string {
  const n = (name ?? '').trim()
  return n || `Split #${splitId.toString()}`
}

/** Bytes a name takes on-chain (UTF-8). The contract allows at most MAX_NAME_BYTES. */
export function nameBytes(name: string): number {
  return new TextEncoder().encode(name).length
}

/** Strip characters the contract rejects (control characters). */
export function cleanName(raw: string): string {
  return raw.replace(/[\u0000-\u001f\u007f]/g, '')
}

/** One split's on-chain name. `name` is "" when the split has none (or while loading). */
export function useSplitName(splitId: bigint | null) {
  const chain = useChain()
  const q = useReadContract({
    address: chain.names.address, abi: chain.names.abi, functionName: 'nameOf',
    args: [splitId ?? 0n], chainId: chain.id,
    query: { enabled: splitId !== null, refetchInterval: 15_000 },
  })
  return { name: ((q.data as string | undefined) ?? '').trim(), loading: q.isLoading, refetch: q.refetch }
}

/** Names for many splits in one request, keyed by split id. */
export function useSplitNames(ids: bigint[]) {
  const chain = useChain()
  const q = useReadContract({
    address: chain.names.address, abi: chain.names.abi, functionName: 'namesOf',
    args: [ids], chainId: chain.id,
    query: { enabled: ids.length > 0, refetchInterval: 15_000 },
  })
  const list = (q.data as string[] | undefined) ?? []
  const names: Record<string, string> = {}
  ids.forEach((id, i) => { names[id.toString()] = (list[i] ?? '').trim() })
  return { names, loading: q.isLoading }
}
