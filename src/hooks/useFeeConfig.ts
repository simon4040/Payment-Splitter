/**
 * Reads the protocol fee settings and owner from the active chain's SplitFactory.
 * Every field is undefined until loaded (or if the contract has no fee support).
 */
import { useReadContract } from 'wagmi'
import { useChain } from '@/hooks/useChain'

export const MAX_FEE_BPS = 500n

/** fee = amount * feeBps / 10_000, mirroring the contract's integer math. */
export function previewFee(amount: bigint, feeBps: bigint): { net: bigint; fee: bigint } {
  const fee = (amount * feeBps) / 10_000n
  return { net: amount - fee, fee }
}

export function useFeeConfig() {
  const chain = useChain()
  const common = { address: chain.factory.address, abi: chain.factory.abi, chainId: chain.id } as const

  const feeBps = useReadContract({ ...common, functionName: 'feeBps', query: { refetchInterval: 15000, retry: false } })
  const feeRecipient = useReadContract({ ...common, functionName: 'feeRecipient', query: { refetchInterval: 15000, retry: false } })
  const owner = useReadContract({ ...common, functionName: 'owner', query: { retry: false } })

  return {
    feeBps: feeBps.data as bigint | number | undefined,
    feeRecipient: feeRecipient.data as `0x${string}` | undefined,
    owner: owner.data as `0x${string}` | undefined,
    refetch: () => { void feeBps.refetch(); void feeRecipient.refetch() },
  }
}
