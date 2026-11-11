import { useState } from 'react'
import { ConnectKitButton } from 'connectkit'
import { Plus, ExternalLink, GitBranch, Sparkles, Users, Wallet, Zap, Loader2, type LucideIcon } from 'lucide-react'
import { useAccount } from 'wagmi'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { useChain } from '@/hooks/useChain'
import { ChainProvider } from '@/components/ChainProvider'
import { ChainSwitcher } from '@/components/ChainSwitcher'
import { BottomNav, type Tab } from '@/components/BottomNav'
import { formatAddress } from '@/utils'
import { CreateSplitSheet } from '@/components/CreateSplitSheet'
import { SplitCard } from '@/components/SplitCard'
import { SplitSelector } from '@/components/SplitSelector'
import { FeeAdminPanel } from '@/components/FeeAdminPanel'
import { PointsPage } from '@/components/PointsPage'
import { BridgePage } from '@/components/BridgePage'
import { LeaderboardPage } from '@/components/LeaderboardPage'
import { useTotalPoints } from '@/hooks/usePoints'
import { SplitHeading } from '@/components/SplitHeading'

const FEATURES: { icon: LucideIcon; label: string; body: string }[] = [
  { icon: Users, label: 'Custom splits', body: 'Name it, add recipients and exact shares.' },
  { icon: Wallet, label: 'Deposit USDC', body: 'Fund any split from your wallet.' },
  { icon: Zap, label: 'One-click payout', body: 'Pay every recipient at once.' },
]

function AppInner() {
  const chain = useChain()
  const explorerUrl = buildAddressExplorerUrl(chain.id, chain.factory.address)
  const { isConnected } = useAccount()
  const [createOpen, setCreateOpen] = useState(false)
  const [switching, setSwitching] = useState(false)
  const [selectedId, setSelectedId] = useState<bigint | null>(null)
  const [tab, setTab] = useState<Tab>('home')
  const totals = useTotalPoints()

  const handleCreated = (id: bigint) => {
    setSelectedId(id)
    setTab('home')
  }

  // Tapping Home while inside a split returns to the list
  const handleChainChange = () => {
    setSelectedId(null)
    setSwitching(true)
    setTimeout(() => setSwitching(false), 900)
  }

  const handleTab = (next: Tab) => {
    if (next === 'home' && tab === 'home') setSelectedId(null)
    setTab(next)
  }

  return (
    <div className="min-h-dvh" style={{ background: 'var(--bg-gradient)' }}>
      {/* Header */}
      <header
        className="sticky top-0 z-30 flex items-center justify-between px-4 py-3"
        style={{
          background: 'rgba(12,12,12,0.88)',
          backdropFilter: 'blur(20px) saturate(140%)',
          WebkitBackdropFilter: 'blur(20px) saturate(140%)',
          borderBottom: '1px solid rgba(245,200,66,0.10)',
        }}
      >
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <div className="size-7 rounded-lg flex items-center justify-center"
              style={{ background: 'rgba(245,200,66,0.12)' }}>
              <GitBranch className="size-3.5" style={{ color: 'var(--accent)' }} />
            </div>
            <span className="display text-base font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>
              Splitter
            </span>
          </div>
          <a
            href={explorerUrl} target="_blank" rel="noreferrer"
            className="hidden sm:flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-70"
            style={{ background: 'rgba(255,255,255,0.06)', color: 'var(--muted)' }}
          >
            <span className="mono">{formatAddress(chain.factory.address)}</span>
            <ExternalLink className="size-3" />
          </a>
        </div>
        <div className="flex items-center gap-2">
          {isConnected && totals.loaded && (
            <button
              onClick={() => setTab('points')}
              className="flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold tabular-nums transition-opacity hover:opacity-80"
              style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)', boxShadow: '0 0 0 1px rgba(245,200,66,0.22)' }}
              title="Your STR points"
            >
              <Sparkles className="size-3.5" />
              {totals.total.toString()} STR
            </button>
          )}
          <ConnectKitButton
            customTheme={{
              '--ck-font-family': "'DM Sans', sans-serif",
              '--ck-primary-button-background': '#F5C842',
              '--ck-primary-button-color': '#0c0c0c',
              '--ck-primary-button-hover-background': '#FFD966',
              '--ck-body-background': '#161616',
              '--ck-body-color': '#ffffff',
              '--ck-body-color-muted': '#a0a0a0',
              '--ck-body-background-secondary': '#1e1e1e',
              '--ck-body-action-color': '#F5C842',
              '--ck-border-radius': '16px',
            }}
          />
        </div>
      </header>

      <main className="mx-auto max-w-md px-4 pt-8 pb-32 space-y-5">
        {/* Network switcher: drives every page (Home, Points, Leaderboard) */}
        <ChainSwitcher onChange={handleChainChange} />
        {switching && (
          <p className="-mt-2 flex items-center justify-center gap-1.5 text-xs" style={{ color: 'var(--muted)' }}>
            <Loader2 className="size-3 animate-spin" /> Loading {chain.label} data…
          </p>
        )}

        {/* One keyed wrapper: when the network changes, the whole page resets and loads fresh data */}
        <div key={`${tab}-${chain.id}`} className="space-y-5">

        {/* ───────── Home ───────── */}
        {tab === 'home' && selectedId === null && (
          <>
            <div className="rounded-3xl p-6" style={{
              background: 'linear-gradient(135deg, rgba(245,200,66,0.07) 0%, rgba(255,255,255,0.02) 100%)',
              border: '1px solid rgba(245,200,66,0.14)',
              boxShadow: '0 8px 40px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.04)',
            }}>
              <button
                onClick={() => setCreateOpen(true)}
                className="w-full inline-flex items-center justify-center gap-2 rounded-2xl px-6 py-4 text-sm font-semibold transition-all active:scale-[0.99]"
                style={{ background: 'var(--accent)', color: '#0c0c0c', boxShadow: '0 4px 28px rgba(245,200,66,0.28)' }}
              >
                <Plus className="size-4" />
                Create New Split
              </button>
              <p className="mt-3 text-center text-xs" style={{ color: 'var(--subtle)' }}>
                {isConnected
                  ? 'Add recipients and shares, send USDC, then distribute in one click.'
                  : 'Connect your wallet to create and manage splits'}
              </p>
            </div>

            {/* Your Splits: always shown, same place every time */}
            <SplitSelector selected={selectedId} onSelect={setSelectedId} onDeselect={() => setSelectedId(null)} />

            {/* Feature cards */}
            <div className="grid grid-cols-3 gap-2.5">
              {FEATURES.map(({ icon: Icon, label, body }) => (
                <div
                  key={label}
                  className="rounded-2xl p-3 flex flex-col gap-2"
                  style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(245,200,66,0.09)' }}
                >
                  <div className="size-7 rounded-lg flex items-center justify-center shrink-0" style={{ background: 'rgba(245,200,66,0.09)' }}>
                    <Icon className="size-3.5" style={{ color: 'var(--accent)' }} />
                  </div>
                  <div>
                    <p className="text-xs font-semibold leading-tight" style={{ color: 'var(--ink)' }}>{label}</p>
                    <p className="mt-0.5 leading-snug" style={{ color: 'var(--muted)', fontSize: '0.68rem' }}>{body}</p>
                  </div>
                </div>
              ))}
            </div>

            {/* Owner-only fee controls (renders nothing for other wallets) */}
            <FeeAdminPanel />
          </>
        )}

        {/* Selected split detail */}
        {tab === 'home' && selectedId !== null && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <button
                onClick={() => setSelectedId(null)}
                className="flex items-center gap-1.5 text-sm font-medium transition-opacity hover:opacity-70"
                style={{ color: 'var(--muted)' }}
              >
                <svg className="size-4" fill="none" viewBox="0 0 16 16">
                  <path d="M10 12L6 8l4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                All splits
              </button>
              <button
                onClick={() => setCreateOpen(true)}
                className="flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-all"
                style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)', boxShadow: '0 0 0 1px rgba(245,200,66,0.20)' }}
              >
                <Plus className="size-3" /> New
              </button>
            </div>

            <SplitHeading key={`${chain.id}-${selectedId.toString()}`} splitId={selectedId} />

            <SplitCard key={`${chain.id}-${selectedId.toString()}`} splitId={selectedId} />
          </div>
        )}

        {/* ───────── Points ───────── */}
        {tab === 'bridge' && <BridgePage />}
        {tab === 'points' && <PointsPage />}

        {/* ───────── Leaderboard ───────── */}
        {tab === 'leaderboard' && <LeaderboardPage />}
        </div>
      </main>

      <BottomNav tab={tab} onChange={handleTab} />

      {/* Create sheet */}
      <CreateSplitSheet open={createOpen} onClose={() => setCreateOpen(false)} onCreated={handleCreated} />
    </div>
  )
}

export default function App() {
  return (
    <ChainProvider>
      <AppInner />
    </ChainProvider>
  )
}
