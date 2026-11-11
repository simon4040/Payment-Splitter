import { Sparkles } from 'lucide-react'
import type { AwardEstimate } from '@/hooks/strTiers'

/** The exact STR this action will earn, shown before the user confirms. */
export function StrNotice({ est, what }: { est: AwardEstimate; what: string }) {
  const warn = est.state === 'below-min' || est.state === 'cap'
  return (
    <p className="flex items-start gap-2 rounded-xl px-3 py-2 text-xs leading-snug" style={{
      background: warn ? 'rgba(251,146,60,0.08)' : 'rgba(245,200,66,0.05)',
      border: `1px solid ${warn ? 'rgba(251,146,60,0.28)' : 'rgba(245,200,66,0.14)'}`,
      color: warn ? '#FDBA74' : 'var(--ink-2)',
    }}>
      <Sparkles className="mt-0.5 size-3.5 shrink-0" style={{ color: warn ? '#FB923C' : 'var(--accent)' }} />
      <span>
        {est.state === 'full' && <>You&rsquo;ll earn <b style={{ color: 'var(--accent)' }}>+{est.award} STR</b> for this {what}</>}
        {est.state === 'partial' && <>You&rsquo;ll earn <b style={{ color: 'var(--accent)' }}>+{est.award} STR</b> for this {what}. It&rsquo;s worth {est.points}, but your daily max of {est.cap} STR only leaves {est.award}</>}
        {est.state === 'cap' && <>Daily max reached ({est.earnedToday}/{est.cap} STR): this {what} earns <b>0 STR</b></>}
        {est.state === 'below-min' && <>Under 1 USDC: this {what} still works but earns <b>0 STR</b></>}
      </span>
    </p>
  )
}
