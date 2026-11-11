/**
 * STR points: the connected wallet's status on the active chain, its total across chains,
 * and the global leaderboard (merged from every chain's StrPoints contract).
 */
import { useEffect, useMemo, useState } from 'react'
import { useAccount, useReadContract, usePublicClient } from 'wagmi'
import { useQuery } from '@tanstack/react-query'
import { parseEventLogs, type Abi, type Log } from 'viem'
import { toast } from 'sonner'
import { CHAINS, CHAIN_KEYS, type ChainKey } from '@/contract'
import { useChain } from '@/hooks/useChain'
import { BASE_DAILY_MAX } from '@/hooks/strTiers'

export const STREAK_LENGTH = 7
/**
 * What the wallet has earned from deposits + distributions today on the active chain, the daily
 * maximum that currently applies, and the highest tier reached today (-1 when none).
 */
export function useActivity() {
  const chain = useChain()
  const { address } = useAccount()
  const act = useReadContract({
    address: chain.points.address, abi: chain.points.abi, chainId: chain.id,
    functionName: 'activityStatus', args: [address!],
    query: { enabled: !!address, refetchInterval: 10_000 },
  })
  const data = act.data as readonly [bigint, bigint, number, boolean] | undefined
  const earnedToday = data ? Number(data[0]) : 0
  const capToday = data ? Number(data[1]) : BASE_DAILY_MAX
  const tierToday = data && data[3] ? Number(data[2]) : -1
  return { earnedToday, capToday, tierToday, remainingToday: Math.max(0, capToday - earnedToday) }
}

/** Tell the user exactly what a deposit/distribution earned, from the transaction's own events. */
export function announceAward(logs: readonly Log[], abi: Abi) {
  const events = parseEventLogs({ abi, logs: logs as Log[], eventName: ['PointsAwarded', 'PointsSkipped'] })
  for (const e of events) {
    const args = e.args as unknown as { amount?: bigint; cause?: number | bigint }
    if (e.eventName === 'PointsAwarded' && args.amount !== undefined) {
      toast.success(`+${args.amount.toString()} STR points`)
      return
    }
    if (e.eventName === 'PointsSkipped') {
      toast.info(Number(args.cause) === 1
        ? 'Under 1 USDC: this earned 0 STR'
        : 'Daily STR limit reached: this earned 0 STR')
      return
    }
  }
}

/** Ticks once a second so countdowns stay live. */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs)
    return () => clearInterval(t)
  }, [intervalMs])
  return now
}

/** Check-in status for the connected wallet on the active chain. */
export function usePointsStatus() {
  const chain = useChain()
  const { address } = useAccount()
  const common = { address: chain.points.address, abi: chain.points.abi, chainId: chain.id } as const

  const status = useReadContract({
    ...common, functionName: 'checkInStatus', args: [address!],
    query: { enabled: !!address, refetchInterval: 10_000 },
  })
  const dayLength = useReadContract({ ...common, functionName: 'dayLength', query: { staleTime: Infinity } })

  const data = status.data as readonly [bigint, number | bigint, boolean, bigint] | undefined
  const points = data ? data[0] : 0n
  const streak = data ? Number(data[1]) : 0
  const canCheckInNow = data ? data[2] : false
  const secondsUntilNext = data ? Number(data[3]) : 0
  // When the next check-in opens, as a local timestamp (derived from when the data was read)
  const nextAt = status.dataUpdatedAt + secondsUntilNext * 1000

  return {
    loaded: !!data,
    points,
    streak,
    canCheckInNow,
    nextAt: canCheckInNow ? 0 : nextAt,
    dayLength: dayLength.data !== undefined ? Number(dayLength.data) : undefined,
  }
}

/** The connected wallet's STR points on each chain, and the sum. */
export function useTotalPoints() {
  const { address } = useAccount()
  const arc = useReadContract({
    address: CHAINS.arc.points.address, abi: CHAINS.arc.points.abi,
    chainId: CHAINS.arc.id, functionName: 'pointsOf', args: [address!],
    query: { enabled: !!address, refetchInterval: 15_000 },
  })
  const base = useReadContract({
    address: CHAINS.base.points.address, abi: CHAINS.base.points.abi,
    chainId: CHAINS.base.id, functionName: 'pointsOf', args: [address!],
    query: { enabled: !!address, refetchInterval: 15_000 },
  })
  const arcPts = (arc.data as bigint | undefined) ?? 0n
  const basePts = (base.data as bigint | undefined) ?? 0n
  return { arc: arcPts, base: basePts, total: arcPts + basePts, loaded: arc.data !== undefined || base.data !== undefined }
}

export type LeaderboardFilter = 'all' | ChainKey

export interface LeaderboardEntry { address: string; points: bigint }

const PAGE = 200n

export function useLeaderboard(filter: LeaderboardFilter) {
  const arcClient = usePublicClient({ chainId: CHAINS.arc.id })
  const baseClient = usePublicClient({ chainId: CHAINS.base.id })
  const clients = useMemo(() => ({ arc: arcClient, base: baseClient }), [arcClient, baseClient])

  return useQuery({
    queryKey: ['leaderboard', filter],
    refetchInterval: 20_000,
    queryFn: async (): Promise<LeaderboardEntry[]> => {
      const keys: ChainKey[] = filter === 'all' ? CHAIN_KEYS : [filter]
      const totals = new Map<string, LeaderboardEntry>()

      await Promise.all(keys.map(async key => {
        const client = clients[key]
        if (!client) return
        const { points } = CHAINS[key]
        const count = (await client.readContract({
          address: points.address, abi: points.abi, functionName: 'userCount',
        })) as bigint
        for (let offset = 0n; offset < count; offset += PAGE) {
          const [users, pts] = (await client.readContract({
            address: points.address, abi: points.abi, functionName: 'getUsers', args: [offset, PAGE],
          })) as [string[], bigint[]]
          users.forEach((u, i) => {
            const id = u.toLowerCase()
            const prev = totals.get(id)
            totals.set(id, { address: u, points: (prev?.points ?? 0n) + (pts[i] ?? 0n) })
          })
        }
      }))

      // Highest points first; ties keep the order users first appeared in
      return [...totals.values()].filter(e => e.points > 0n).sort((a, b) => (a.points === b.points ? 0 : a.points > b.points ? -1 : 1))
    },
  })
}
