/**
 * Points page: total STR, 7-day check-in streak, daily check-in, and how points work.
 */
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { Loader2, Check, Sparkles } from 'lucide-react'
import { toast } from 'sonner'
import { useChain } from '@/hooks/useChain'
import { usePointsStatus, useTotalPoints, useNow, useActivity, STREAK_LENGTH } from '@/hooks/usePoints'
import { TIERS } from '@/hooks/strTiers'
import { parseOnchainError } from '@/utils'
import { DATA_SUFFIX } from '@/attribution'

function fmtCountdown(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const mm = String(m).padStart(2, '0')
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}

const RULES: { amount: string; label: string }[] = [
  { amount: '+5', label: 'Daily check-in' },
  { amount: '+25', label: 'Bonus on day 7 of your streak' },
]

const card: React.CSSProperties = {
  background: 'rgba(255,255,255,0.035)',
  border: '1px solid rgba(245,200,66,0.12)',
  boxShadow: '0 4px 24px rgba(0,0,0,0.24)',
}

export function PointsPage() {
  const chain = useChain()
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const queryClient = useQueryClient()
  const status = usePointsStatus()
  const totals = useTotalPoints()
  const now = useNow()
  const activity = useActivity()

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash, query: { enabled: !!hash } })

  const isWrongChain = isConnected && chainId !== chain.id
  const busy = isPending || isConfirming
  const waitMs = status.nextAt - now
  const waiting = !status.canCheckInNow && status.loaded && waitMs > 0
  const bonusNext = status.streak === STREAK_LENGTH - 1

  const checkIn = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    const willBonus = bonusNext
    writeContract({
      address: chain.points.address, abi: chain.points.abi, functionName: 'checkIn', chainId: chain.id, dataSuffix: DATA_SUFFIX,
    }, {
      onSuccess: () => {
        toast.success(willBonus ? '+30 STR points: 7-day streak bonus!' : '+5 STR points')
        // Give the node a moment to index the receipt, then refresh points + leaderboard
        setTimeout(() => void queryClient.invalidateQueries(), 2500)
      },
      onError: (e) => toast.error(parseOnchainError(e)),
    })
  }

  return (
    <div className="space-y-4">
      {/* Total */}
      <div className="rounded-3xl p-7" style={{
        background: 'linear-gradient(135deg, rgba(245,200,66,0.09) 0%, rgba(255,255,255,0.025) 100%)',
        border: '1px solid rgba(245,200,66,0.20)',
        boxShadow: '0 8px 40px rgba(0,0,0,0.34), inset 0 1px 0 rgba(255,255,255,0.05)',
      }}>
        <div className="flex items-center gap-2 mb-5">
          <Sparkles className="size-3.5" style={{ color: 'var(--accent)' }} />
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
            Total STR points
          </span>
        </div>
        <div className="flex items-baseline gap-2.5">
          <span className="display font-bold tabular-nums" style={{ color: 'var(--ink)', fontSize: 'clamp(3rem,12vw,3.8rem)', letterSpacing: '-0.04em', lineHeight: 1 }}>
            {isConnected ? totals.total.toString() : '0'}
          </span>
          <span className="text-xl font-medium" style={{ color: 'var(--accent)' }}>STR</span>
        </div>
        <p className="mt-3 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
          Arc {isConnected ? totals.arc.toString() : '0'} · Base {isConnected ? totals.base.toString() : '0'}
        </p>
      </div>

      {/* Check-in */}
      <div className="rounded-3xl p-6" style={card}>
        <div className="mb-4 flex items-center justify-between">
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
            Check-in streak
          </span>
          <span className="display text-lg font-bold tabular-nums" style={{ color: 'var(--accent)' }}>
            {status.streak}<span className="text-sm font-medium" style={{ color: 'var(--muted)' }}> / {STREAK_LENGTH}</span>
          </span>
        </div>

        <div className="mb-5 flex gap-1.5">
          {Array.from({ length: STREAK_LENGTH }, (_, i) => {
            const filled = i < status.streak
            const isBonus = i === STREAK_LENGTH - 1
            return (
              <div key={i} className="flex-1 h-11 rounded-xl flex items-center justify-center text-xs font-semibold" style={{
                background: filled ? 'var(--accent)' : 'rgba(255,255,255,0.05)',
                color: filled ? '#0c0c0c' : isBonus ? 'var(--accent)' : 'var(--subtle)',
                boxShadow: filled ? '0 0 14px rgba(245,200,66,0.25)' : `0 0 0 1px ${isBonus ? 'rgba(245,200,66,0.30)' : 'rgba(255,255,255,0.08)'}`,
              }}>
                {filled ? <Check className="size-4" /> : isBonus ? '+25' : i + 1}
              </div>
            )
          })}
        </div>

        {!isConnected ? (
          <p className="py-2 text-center text-sm" style={{ color: 'var(--muted)' }}>Connect your wallet to check in and earn STR</p>
        ) : (
          <button
            onClick={checkIn}
            disabled={(!status.canCheckInNow && !isWrongChain) || busy}
            className="w-full rounded-2xl py-4 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed flex items-center justify-center gap-2"
            style={{
              background: status.canCheckInNow || isWrongChain ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
              color: status.canCheckInNow || isWrongChain ? '#0c0c0c' : 'var(--muted)',
              boxShadow: status.canCheckInNow && !busy ? '0 4px 28px rgba(245,200,66,0.26)' : 'none',
              opacity: !status.canCheckInNow && !isWrongChain ? 0.7 : 1,
            }}
          >
            {isWrongChain ? 'Switch Network'
              : busy ? <><Loader2 className="size-4 animate-spin" />{isPending ? 'Confirm in wallet…' : 'Checking in…'}</>
              : waiting ? `Checked in · next in ${fmtCountdown(waitMs)}`
              : bonusNext ? 'Daily check-in · +30 STR (7-day bonus)'
              : 'Daily check-in · +5 STR'}
          </button>
        )}

        <p className="mt-3 text-center text-xs" style={{ color: 'var(--subtle)' }}>
          Checking in on {chain.label}. Streaks are tracked per network. A new check-in day starts at 00:00 UTC.
        </p>
      </div>

      {/* Today's deposit/distribution allowance */}
      <div className="rounded-3xl p-6" style={card}>
        <div className="mb-3 flex items-center justify-between">
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
            Deposits, distributions &amp; bridges today
          </span>
          <span className="display text-sm font-bold tabular-nums" style={{ color: 'var(--accent)' }}>
            {isConnected ? activity.earnedToday : 0}<span className="font-medium" style={{ color: 'var(--muted)' }}> / {isConnected ? activity.capToday : TIERS[0].dailyMax} STR</span>
          </span>
        </div>
        <div className="h-1.5 overflow-hidden rounded-full" style={{ background: 'rgba(255,255,255,0.08)' }}>
          <div className="h-full rounded-full transition-all duration-500" style={{
            width: `${Math.min(100, ((isConnected ? activity.earnedToday : 0) / (isConnected ? activity.capToday : TIERS[0].dailyMax)) * 100)}%`,
            background: 'var(--accent)',
          }} />
        </div>
        <p className="mt-3 text-xs leading-relaxed" style={{ color: 'var(--subtle)' }}>
          Your daily max starts at 50 STR and rises when you make a larger deposit or distribution. Daily check-ins don&rsquo;t count toward it.
        </p>
      </div>

      {/* Tiers */}
      <div className="rounded-3xl p-6" style={card}>
        <span className="mb-4 block text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
          Deposits, distributions &amp; bridges
        </span>
        <div className="mb-2 grid grid-cols-[1fr_auto_auto] gap-x-4 px-4 text-[0.65rem] font-semibold uppercase tracking-wider" style={{ color: 'var(--subtle)' }}>
          <span>Amount (USDC)</span><span className="w-14 text-right">STR</span><span className="w-16 text-right">Daily max</span>
        </div>
        <ul className="space-y-2">
          {TIERS.map((t, i) => {
            const reached = isConnected && activity.tierToday >= i
            return (
              <li key={t.range} className="grid grid-cols-[1fr_auto_auto] items-center gap-x-4 rounded-2xl px-4 py-3" style={{
                background: reached ? 'rgba(245,200,66,0.07)' : 'rgba(255,255,255,0.03)',
                border: `1px solid ${reached ? 'rgba(245,200,66,0.22)' : 'rgba(245,200,66,0.08)'}`,
              }}>
                <span className="text-sm tabular-nums" style={{ color: 'var(--ink-2)' }}>{t.range}</span>
                <span className="display w-14 text-right text-base font-bold tabular-nums" style={{ color: 'var(--accent)' }}>+{t.points}</span>
                <span className="w-16 text-right text-sm tabular-nums" style={{ color: 'var(--muted)' }}>{t.dailyMax}</span>
              </li>
            )
          })}
        </ul>
        <p className="mt-3 text-xs leading-relaxed" style={{ color: 'var(--subtle)' }}>
          Under 1 USDC still works but earns 0 STR. A deposit or bridge counts by the amount you send; a distribution counts by the split&rsquo;s balance after the protocol fee.
        </p>
      </div>

      {/* How points work */}
      <div className="rounded-3xl p-6" style={card}>
        <span className="mb-4 block text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>
          How points work
        </span>
        <ul className="space-y-2.5">
          {RULES.map(r => (
            <li key={r.label} className="flex items-center justify-between rounded-2xl px-4 py-3" style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(245,200,66,0.08)' }}>
              <span className="text-sm" style={{ color: 'var(--ink-2)' }}>{r.label}</span>
              <span className="display text-base font-bold tabular-nums" style={{ color: 'var(--accent)' }}>{r.amount}</span>
            </li>
          ))}
        </ul>
        <p className="mt-3 text-xs leading-relaxed" style={{ color: 'var(--subtle)' }}>
          Missing a day resets your streak. After the day-7 bonus the streak starts over.
        </p>
      </div>
    </div>
  )
}
