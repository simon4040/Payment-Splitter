/**
 * CCTP bridging helpers: Circle's fee quote + transfer status APIs, the fee math shown before
 * the user confirms, and the in-progress transfer record that survives a page reload.
 *
 * The status/fee API base URL comes from src/network.ts (testnet and mainnet differ).
 */
import { useSyncExternalStore } from 'react'
import { IRIS_API } from '@/network'

/** CCTP "Fast Transfer" finality threshold. */
export const FAST_FINALITY = 1000
/** How often the tracker checks the transfer and the destination balance. */
export const BRIDGE_POLL_MS = 2000
/** Give up waiting (and let the user dismiss) after this long. */
export const BRIDGE_SLOW_MS = 15 * 60 * 1000

export interface FeeQuote {
  /** CCTP protocol fee for fast transfers, in basis points. */
  protocolBps: number
  /** Forwarding Service fee (USDC base units), typical and high-priority levels. */
  forwardMed: bigint
  forwardHigh: bigint
}

export async function fetchFeeQuote(srcDomain: number, dstDomain: number): Promise<FeeQuote> {
  const res = await fetch(`${IRIS_API}/v2/burn/USDC/fees/${srcDomain}/${dstDomain}?forward=true`)
  if (!res.ok) throw new Error('Could not load Circle network fees')
  const rows = (await res.json()) as Array<{
    finalityThreshold: number
    minimumFee: number
    forwardFee?: { med: number; high: number }
  }>
  const fast = rows.find(r => r.finalityThreshold === FAST_FINALITY)
  if (!fast?.forwardFee) throw new Error('Circle fee quote unavailable for this route')
  return {
    protocolBps: fast.minimumFee,
    forwardMed: BigInt(fast.forwardFee.med),
    forwardHigh: BigInt(fast.forwardFee.high),
  }
}

export interface BridgeQuote {
  /** What the wallet sends. */
  amount: bigint
  /** Platform fee, taken by the contract from `amount` (same fee as the splits). */
  platformFee: bigint
  /** Amount burned on the source chain. */
  burn: bigint
  /** Network fee (protocol + delivery) taken from the burn. Equals the ceiling: it is charged in full. */
  networkFeeEst: bigint
  /** Fee ceiling passed to CCTP. */
  maxFee: bigint
  /** Amount minted to the recipient: the burn minus the network fee. */
  receiveEst: bigint
  /** Same value; kept as the lower bound the tracker waits for on the destination chain. */
  receiveMin: bigint
  /** False when the amount cannot cover the fees. */
  valid: boolean
}

export function computeBridge(amount: bigint, feeBps: bigint, q: FeeQuote): BridgeQuote {
  const platformFee = (amount * feeBps) / 10_000n
  const burn = amount - platformFee
  const bpsScaled = BigInt(Math.round(q.protocolBps * 100)) // hundredths of a basis point
  const protocolFee = (burn * bpsScaled + 999_999n) / 1_000_000n // round up so the ceiling always covers it
  const maxFee = protocolFee + q.forwardHigh + 1n
  // The network fee has been charged at exactly the ceiling on every transfer observed, so show it as such.
  const networkFeeEst = maxFee
  const valid = amount > 0n && maxFee < burn
  return {
    amount,
    platformFee,
    burn,
    networkFeeEst,
    maxFee,
    receiveEst: burn > maxFee ? burn - maxFee : 0n,
    receiveMin: burn > maxFee ? burn - maxFee : 0n,
    valid,
  }
}

// ─── Transfer status (Circle Iris) ────────────────────────────────────────────

export type BridgeStage = 'attesting' | 'forwarding' | 'complete' | 'failed'

export async function fetchBridgeStatus(
  srcDomain: number,
  txHash: string,
): Promise<{ stage: BridgeStage; mintTx?: string }> {
  const res = await fetch(`${IRIS_API}/v2/messages/${srcDomain}?transactionHash=${txHash}`)
  if (res.status === 404) return { stage: 'attesting' } // not indexed yet
  if (!res.ok) throw new Error('Could not load transfer status')
  const body = (await res.json()) as {
    messages?: Array<{ status?: string; forwardState?: string; forwardTxHash?: string; destinationMintTxHash?: string }>
  }
  const m = body.messages?.[0]
  if (!m) return { stage: 'attesting' }
  const fwd = (m.forwardState ?? '').toUpperCase()
  if (fwd === 'FAILED') return { stage: 'failed' }
  if (fwd === 'COMPLETE') return { stage: 'complete', mintTx: m.destinationMintTxHash ?? m.forwardTxHash }
  if (m.status === 'complete') return { stage: 'forwarding' }
  return { stage: 'attesting' }
}

// ─── In-progress transfer (kept in localStorage so a reload keeps tracking it) ─

export interface PendingBridge {
  txHash: `0x${string}`
  srcChainId: number
  dstChainId: number
  srcDomain: number
  /** Human strings, for display only. */
  amount: string
  receive: string
  startedAt: number
  /** Lets the tracker see the mint land on the destination chain without waiting for the status service. */
  recipient: `0x${string}`
  dstUsdc: `0x${string}`
  /** Recipient's USDC balance on the destination chain when the bridge started (base units), or null. */
  dstBalanceBefore: string | null
  /** The least the recipient receives (base units). */
  minReceive: string
}

const EVT = 'pending-bridge-change'
const keyFor = (addr: string) => `pending-bridge-${addr.toLowerCase()}`

function subscribe(cb: () => void) {
  window.addEventListener(EVT, cb)
  window.addEventListener('storage', cb)
  return () => {
    window.removeEventListener(EVT, cb)
    window.removeEventListener('storage', cb)
  }
}

export function usePendingBridge(address: string | undefined) {
  const raw = useSyncExternalStore(
    subscribe,
    () => {
      try { return address ? localStorage.getItem(keyFor(address)) : null } catch { return null }
    },
    () => null,
  )
  let pending: PendingBridge | null = null
  if (raw) {
    try { pending = JSON.parse(raw) as PendingBridge } catch { pending = null }
  }
  const setPending = (p: PendingBridge) => {
    if (!address) return
    try { localStorage.setItem(keyFor(address), JSON.stringify(p)) } catch { /* storage unavailable */ }
    window.dispatchEvent(new Event(EVT))
  }
  const clearPending = () => {
    if (!address) return
    try { localStorage.removeItem(keyFor(address)) } catch { /* storage unavailable */ }
    window.dispatchEvent(new Event(EVT))
  }
  return { pending, setPending, clearPending }
}
