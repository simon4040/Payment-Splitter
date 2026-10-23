/**
 * Returns all split IDs created by a given address.
 *
 * Strategy: read splitCount from the contract, then call getSplit(1..splitCount)
 * in parallel and filter by creator === address. This avoids eth_getLogs entirely,
 * sidestepping Arc Testnet's block-range cap that made the previous getLogs-based
 * approach silently fail or loop indefinitely.
 */
import { useState, useEffect, useRef } from 'react'
import { usePublicClient, useReadContract } from 'wagmi'
import { SPLIT_FACTORY, ARC_MAINNET_ID } from '@/contract'

export function useSplitIds(creator: string | undefined): { ids: bigint[]; loading: boolean } {
  const [ids, setIds] = useState<bigint[]>([])
  const [loading, setLoading] = useState(false)
  const client = usePublicClient({ chainId: ARC_MAINNET_ID })
  const cancelRef = useRef(false)

  const { data: splitCountData } = useReadContract({
    address: SPLIT_FACTORY.address,
    abi: SPLIT_FACTORY.abi,
    functionName: 'splitCount',
    chainId: ARC_MAINNET_ID,
    query: { refetchInterval: 10_000 },
  })
  const splitCount = splitCountData as bigint | undefined

  useEffect(() => {
    cancelRef.current = false

    const run = async () => {
      // Nothing to scan
      if (!creator || !client || splitCount === undefined || splitCount === 0n) {
        setIds([])
        setLoading(false)
        return
      }

      setLoading(true)
      try {
        const total = Number(splitCount)
        // Batch all getSplit calls in parallel — each is a single eth_call
        const calls = Array.from({ length: total }, (_, i) =>
          client.readContract({
            address: SPLIT_FACTORY.address,
            abi: SPLIT_FACTORY.abi,
            functionName: 'getSplit',
            args: [BigInt(i + 1)],
          }) as Promise<[string, bigint, bigint, bigint]>
        )
        const results = await Promise.allSettled(calls)
        if (cancelRef.current) return

        const mine: bigint[] = []
        for (let i = 0; i < results.length; i++) {
          const r = results[i]
          if (r.status === 'fulfilled') {
            const [splitCreator] = r.value
            if (splitCreator.toLowerCase() === creator.toLowerCase()) {
              mine.push(BigInt(i + 1))
            }
          }
        }
        if (!cancelRef.current) setIds(mine)
      } catch {
        if (!cancelRef.current) setIds([])
      } finally {
        if (!cancelRef.current) setLoading(false)
      }
    }

    void run()
    return () => { cancelRef.current = true }
  }, [creator, client, splitCount])

  return { ids, loading }
}
