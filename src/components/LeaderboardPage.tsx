/**
 * Global STR leaderboard: every wallet ranked by total points, across both networks.
 */
import { useState } from 'react'
import { useAccount } from 'wagmi'
import { Medal, Trophy } from 'lucide-react'
import { CHAINS, CHAIN_KEYS } from '@/contract'
import { useChain } from '@/hooks/useChain'
import { useLeaderboard, type LeaderboardFilter } from '@/hooks/usePoints'
import { formatAddress } from '@/utils'

const MEDALS = [
  { name: 'Gold', color: '#F5C842', bg: 'rgba(245,200,66,0.14)', ring: 'rgba(245,200,66,0.40)' },
  { name: 'Silver', color: '#D3D8DF', bg: 'rgba(211,216,223,0.12)', ring: 'rgba(211,216,223,0.35)' },
  { name: 'Bronze', color: '#D08A4E', bg: 'rgba(208,138,78,0.14)', ring: 'rgba(208,138,78,0.38)' },
] as const

const SHOWN = 100

export function LeaderboardPage() {
  const chain = useChain()
  const [filter, setFilter] = useState<LeaderboardFilter>(chain.key)
  const { address } = useAccount()
  const { data, isLoading, isError } = useLeaderboard(filter)

  const entries = data ?? []
  const me = address?.toLowerCase()
  const myIndex = me ? entries.findIndex(e => e.address.toLowerCase() === me) : -1
  const filters: { key: LeaderboardFilter; label: string }[] = [
    { key: 'all', label: 'All' },
    ...CHAIN_KEYS.map(k => ({ key: k as LeaderboardFilter, label: CHAINS[k].label })),
  ]

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-2">
        <Trophy className="size-4" style={{ color: 'var(--accent)' }} />
        <h1 className="display text-lg font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>Leaderboard</h1>
      </div>

      {/* Network filter */}
      <div className="mx-auto flex w-fit items-center gap-1 rounded-2xl p-1" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(245,200,66,0.12)' }}>
        {filters.map(f => {
          const active = filter === f.key
          return (
            <button key={f.key} onClick={() => setFilter(f.key)}
              className="rounded-xl px-4 py-1.5 text-xs font-semibold transition-all"
              style={{ background: active ? 'var(--accent)' : 'transparent', color: active ? '#0c0c0c' : 'var(--muted)', minWidth: '4.25rem' }}>
              {f.label}
            </button>
          )
        })}
      </div>

      {myIndex >= 0 && (
        <div className="rounded-2xl px-4 py-3 flex items-center justify-between" style={{ background: 'rgba(245,200,66,0.07)', border: '1px solid rgba(245,200,66,0.22)' }}>
          <span className="text-xs font-medium" style={{ color: 'var(--ink-2)' }}>Your rank</span>
          <span className="text-sm font-semibold tabular-nums" style={{ color: 'var(--accent)' }}>
            #{myIndex + 1} · {entries[myIndex].points.toString()} STR
          </span>
        </div>
      )}

      <div className="rounded-3xl overflow-hidden" style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(245,200,66,0.12)', boxShadow: '0 8px 32px rgba(0,0,0,0.28)' }}>
        <div className="grid grid-cols-[3.5rem_1fr_auto] gap-3 px-5 py-3 text-xs font-semibold uppercase" style={{ color: 'var(--subtle)', letterSpacing: '0.08em', borderBottom: '1px solid rgba(245,200,66,0.10)' }}>
          <span>Rank</span><span>Wallet</span><span className="text-right">STR</span>
        </div>

        {isLoading ? (
          <div className="p-4 space-y-2.5">
            {[1, 2, 3, 4].map(i => <div key={i} className="h-12 rounded-xl animate-pulse" style={{ background: 'rgba(255,255,255,0.06)' }} />)}
          </div>
        ) : isError ? (
          <p className="py-12 text-center text-sm" style={{ color: 'var(--muted)' }}>Couldn&apos;t load the leaderboard. Please try again.</p>
        ) : entries.length === 0 ? (
          <div className="py-14 px-6 text-center">
            <div className="size-12 rounded-2xl mx-auto mb-4 flex items-center justify-center" style={{ background: 'rgba(245,200,66,0.08)', border: '1px solid rgba(245,200,66,0.16)' }}>
              <Trophy className="size-5" style={{ color: 'var(--accent)' }} />
            </div>
            <p className="text-sm font-medium" style={{ color: 'var(--ink-2)' }}>No points yet</p>
            <p className="text-xs mt-1" style={{ color: 'var(--subtle)' }}>Check in, deposit or distribute to take the first spot.</p>
          </div>
        ) : (
          <ul>
            {entries.slice(0, SHOWN).map((e, i) => {
              const medal = i < 3 ? MEDALS[i] : null
              const mine = e.address.toLowerCase() === me
              return (
                <li key={e.address} className="grid grid-cols-[3.5rem_1fr_auto] items-center gap-3 px-5 py-3.5" style={{
                  background: mine ? 'rgba(245,200,66,0.06)' : medal ? medal.bg.replace(/0\.1\d/, '0.05') : 'transparent',
                  borderBottom: i === Math.min(entries.length, SHOWN) - 1 ? 'none' : '1px solid rgba(255,255,255,0.05)',
                }}>
                  <div>
                    {medal ? (
                      <div className="size-9 rounded-full flex items-center justify-center" title={`${medal.name} medal`} style={{ background: medal.bg, boxShadow: `0 0 0 1.5px ${medal.ring}` }}>
                        <Medal className="size-4" style={{ color: medal.color }} strokeWidth={2.2} />
                      </div>
                    ) : (
                      <span className="display text-sm font-semibold tabular-nums pl-2" style={{ color: 'var(--muted)' }}>{i + 1}</span>
                    )}
                  </div>
                  <div className="min-w-0 flex items-center gap-2">
                    <span className="mono text-sm" style={{ color: medal ? medal.color : 'var(--ink-2)' }}>{formatAddress(e.address)}</span>
                    {mine && <span className="rounded-full px-2 py-0.5 text-xs font-semibold" style={{ background: 'rgba(245,200,66,0.14)', color: 'var(--accent)' }}>You</span>}
                  </div>
                  <span className="display text-base font-bold tabular-nums text-right" style={{ color: medal ? medal.color : 'var(--ink)' }}>
                    {e.points.toString()}
                  </span>
                </li>
              )
            })}
          </ul>
        )}
      </div>

      <p className="text-center text-xs" style={{ color: 'var(--subtle)' }}>
        Ranked by total STR across both networks · updates after deposits, distributions and check-ins
      </p>
    </div>
  )
}
