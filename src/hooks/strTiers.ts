/**
 * STR points tiers for deposits and distributions. Mirrors the on-chain StrPoints contract
 * (USDC has 6 decimals). The contract is the source of truth for what is actually awarded;
 * this table only powers the "you will earn" preview and the Points page.
 */
export interface Tier {
  /** Lower bound in USDC (inclusive). */
  minUsdc: number
  /** Human range label. */
  range: string
  points: number
  /** Daily maximum once the wallet has reached this tier today. */
  dailyMax: number
}

export const TIERS: readonly Tier[] = [
  { minUsdc: 1, range: '1 – 9.99', points: 5, dailyMax: 50 },
  { minUsdc: 10, range: '10 – 49.99', points: 25, dailyMax: 75 },
  { minUsdc: 50, range: '50 – 99.99', points: 50, dailyMax: 100 },
  { minUsdc: 100, range: '100 – 249.99', points: 75, dailyMax: 150 },
  { minUsdc: 250, range: '250 – 999.99', points: 100, dailyMax: 200 },
  { minUsdc: 1000, range: '1,000 +', points: 150, dailyMax: 600 },
]

export const BASE_DAILY_MAX = 50
const USDC_UNIT = 1_000_000n

/** Tier index for an amount in USDC base units, or -1 when it is below 1 USDC. */
export function tierIndexOf(amount: bigint): number {
  let idx = -1
  for (let i = 0; i < TIERS.length; i++) {
    if (amount >= BigInt(TIERS[i].minUsdc) * USDC_UNIT) idx = i
  }
  return idx
}

export interface AwardEstimate {
  /** What this amount is worth on its own. */
  points: number
  /** What the wallet will actually receive after today's daily maximum. */
  award: number
  /** Daily maximum that will apply after this action. */
  cap: number
  earnedToday: number
  state: 'below-min' | 'full' | 'partial' | 'cap'
}

/**
 * Exact STR a deposit/distribution of `amount` will earn, given what the wallet already earned today
 * and the highest tier it reached today (-1 for none). The tier is raised before the cap is applied.
 */
export function estimateAward(amount: bigint, earnedToday: number, tierToday: number): AwardEstimate {
  const t = tierIndexOf(amount)
  if (t < 0) return { points: 0, award: 0, cap: tierToday >= 0 ? TIERS[tierToday].dailyMax : BASE_DAILY_MAX, earnedToday, state: 'below-min' }
  const highest = Math.max(t, tierToday)
  const cap = TIERS[highest].dailyMax
  const remaining = Math.max(0, cap - earnedToday)
  const points = TIERS[t].points
  const award = Math.min(points, remaining)
  return { points, award, cap, earnedToday, state: award === 0 ? 'cap' : award < points ? 'partial' : 'full' }
}
