/**
 * Contract ABIs and the per-chain setup the whole app reads. Chain ids, token and contract addresses
 * come from src/network.ts; ABIs are the committed files in src/abi (refresh with `bun run abi:sync`).
 */
import splitFactory from './abi/SplitFactory.json'
import strPoints from './abi/StrPoints.json'
import splitNames from './abi/SplitNames.json'
import recipientLabels from './abi/RecipientLabels.json'
import { NETWORK } from './network'

export const SPLIT_ABI = splitFactory.abi
export const POINTS_ABI = strPoints.abi
export const NAMES_ABI = splitNames.abi
export const LABELS_ABI = recipientLabels.abi

export type ChainKey = 'arc' | 'base'

export interface ChainSetup {
  key: ChainKey
  /** Short name shown in the UI switcher */
  label: string
  /** EVM chain id */
  id: number
  /** Circle CCTP domain, used by the bridge */
  cctpDomain: number
  /** Official USDC token on this chain (6 decimals) */
  usdc: `0x${string}`
  /** The SplitFactory deployed on this chain. Each chain has its own independent splits. */
  factory: { address: `0x${string}`; abi: typeof SPLIT_ABI }
  /**
   * StrPoints wraps the factory's deposit/distribute so STR points are only awarded for real,
   * successful calls. It also holds daily check-ins, the leaderboard data and the bridge.
   */
  points: { address: `0x${string}`; abi: typeof POINTS_ABI }
  /** On-chain split names (set by each split's creator). Read from the blockchain, never from browser storage. */
  names: { address: `0x${string}`; abi: typeof NAMES_ABI }
  /** On-chain recipient names/tags (set by each split's creator). */
  labels?: { address: `0x${string}`; abi: typeof LABELS_ABI }
}

const ZERO = '0x0000000000000000000000000000000000000000'

// Refuse to start with a contract address that was never filled in (mainnet placeholders), rather
// than sending funds to the zero address.
const unset = (['arc', 'base'] as const).flatMap(k =>
  (['factory', 'points', 'names', 'labels'] as const)
    .filter(f => NETWORK[k][f].toLowerCase() === ZERO)
    .map(f => `${k}.${f}`),
)
if (unset.length > 0) {
  throw new Error(`src/network.ts is missing deployed contract addresses: ${unset.join(', ')}`)
}

function setup(key: ChainKey, label: string): ChainSetup {
  const n = NETWORK[key]
  return {
    key,
    label,
    id: n.id,
    cctpDomain: n.cctpDomain,
    usdc: n.usdc,
    factory: { address: n.factory, abi: SPLIT_ABI },
    points: { address: n.points, abi: POINTS_ABI },
    names: { address: n.names, abi: NAMES_ABI },
    labels: { address: n.labels, abi: LABELS_ABI },
  }
}

export const CHAINS: Record<ChainKey, ChainSetup> = {
  arc: setup('arc', 'Arc'),
  base: setup('base', 'Base'),
}

export const CHAIN_KEYS: ChainKey[] = ['arc', 'base']
