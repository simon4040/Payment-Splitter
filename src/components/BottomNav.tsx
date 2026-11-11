import { ArrowLeftRight, Home, Sparkles, Trophy } from 'lucide-react'

export type Tab = 'home' | 'bridge' | 'points' | 'leaderboard'

const ITEMS: { key: Tab; label: string; icon: typeof Home }[] = [
  { key: 'home', label: 'Home', icon: Home },
  { key: 'bridge', label: 'Bridge', icon: ArrowLeftRight },
  { key: 'points', label: 'Points', icon: Sparkles },
  { key: 'leaderboard', label: 'Leaderboard', icon: Trophy },
]

/** Fixed bottom navigation: Home / Bridge / Points / Leaderboard. */
export function BottomNav({ tab, onChange }: { tab: Tab; onChange: (t: Tab) => void }) {
  return (
    <nav
      aria-label="Main"
      className="fixed inset-x-0 bottom-0 z-40"
      style={{
        background: 'rgba(12,12,12,0.92)',
        backdropFilter: 'blur(20px) saturate(140%)',
        WebkitBackdropFilter: 'blur(20px) saturate(140%)',
        borderTop: '1px solid rgba(245,200,66,0.12)',
        paddingBottom: 'env(safe-area-inset-bottom)',
      }}
    >
      <div className="mx-auto flex max-w-md items-stretch justify-around px-3 py-2">
        {ITEMS.map(({ key, label, icon: Icon }) => {
          const active = tab === key
          return (
            <button
              key={key}
              onClick={() => onChange(key)}
              aria-current={active ? 'page' : undefined}
              className="flex flex-1 flex-col items-center gap-1 rounded-2xl py-2 transition-all active:scale-[0.97]"
              style={{ color: active ? 'var(--accent)' : 'var(--subtle)' }}
            >
              <span
                className="flex h-7 w-12 items-center justify-center rounded-full transition-all"
                style={{ background: active ? 'rgba(245,200,66,0.14)' : 'transparent' }}
              >
                <Icon className="size-[1.15rem]" strokeWidth={active ? 2.3 : 1.9} />
              </span>
              <span className="text-xs font-semibold" style={{ letterSpacing: '0.01em' }}>{label}</span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
