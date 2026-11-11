/**
 * Returns the split IDs created by a given address on the ACTIVE chain only.
 *
 * Strategy: read splitCount from the chain's factory, then call getSplit(1..splitCount)
 * in parallel and keep the ones whose creator matches. No eth_getLogs, so RPC block-range
 * caps do not apply.
 *
 * The result is cached per (chain, factory, wallet, splitCount) in react-query, so a list
 * from one chain can never be shown, merged or multiplied on another chain. IDs are
 * de-duplicated and sorted ascending.
 */
import { useQuery } from '@tanstack/react-query'
import { usePublicClient, useReadContract } from 'wagmi'
import { useChain } from '@/hooks/useChain'

export function useSplitIds(creator: string | undefined): { ids: bigint[]; loading: boolean } {
  const chain = useChain()
  const client = usePublicClient({ chainId: chain.id })

  const count = useReadContract({
    address: chain.factory.address,
    abi: chain.factory.abi,
    functionName: 'splitCount',
    chainId: chain.id,
    query: { refetchInterval: 10_000 },
  })
  const splitCount = count.data as bigint | undefined
  const hasSplits = splitCount !== undefined && splitCount > 0n

  const mine = useQuery({
    queryKey: [
      'my-splits',
      chain.id,
      chain.factory.address.toLowerCase(),
      creator?.toLowerCase() ?? '',
      splitCount?.toString() ?? '',
    ],
    enabled: !!creator && !!client && hasSplits,
    staleTime: 10_000,
    queryFn: async (): Promise<bigint[]> => {
      if (!creator || !client || splitCount === undefined) return []
      const total = Number(splitCount)
      const results = await Promise.allSettled(
        Array.from({ length: total }, (_, i) =>
          client.readContract({
            address: chain.factory.address,
            abi: chain.factory.abi,
            functionName: 'getSplit',
            args: [BigInt(i + 1)],
          }) as Promise<[string, bigint, bigint, bigint]>
        )
      )
      const found = new Set<string>()
      results.forEach((r, i) => {
        if (r.status === 'fulfilled' && r.value[0].toLowerCase() === creator.toLowerCase()) {
          found.add((i + 1).toString())
        }
      })
      return [...found].map(s => BigInt(s)).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
    },
  })

  if (!creator) return { ids: [], loading: false }
  // Still working out how many splits this chain has
  if (count.isLoading) return { ids: [], loading: true }
  if (!hasSplits) return { ids: [], loading: false }
  return { ids: mine.data ?? [], loading: mine.isLoading }
}
