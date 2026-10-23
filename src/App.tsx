import { useState } from 'react'
import { ConnectKitButton } from 'connectkit'
import { Plus, ExternalLink, GitBranch, Wallet, Users, Zap } from 'lucide-react'
import { useAccount } from 'wagmi'
import { SPLIT_FACTORY } from '@/contract'
import { formatAddress } from '@/utils'
import { CreateSplitSheet } from '@/components/CreateSplitSheet'
import { SplitCard } from '@/components/SplitCard'
import { SplitSelector } from '@/components/SplitSelector'
import { splitLabel, getSplitTitle } from '@/hooks/useSplitTitle'

const EXPLORER_URL = `https://explorer.testnet.arc.io/address/${SPLIT_FACTORY.address}`

export default function App() {
  const { isConnected } = useAccount()
  const [createOpen, setCreateOpen] = useState(false)
  const [selectedId, setSelectedId] = useState<bigint | null>(null)

  const handleCreated = (id: bigint) => { setSelectedId(id) }

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
            href={EXPLORER_URL} target="_blank" rel="noreferrer"
            className="hidden sm:flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-70"
            style={{ background: 'rgba(255,255,255,0.06)', color: 'var(--muted)' }}
          >
            <span className="mono">{formatAddress(SPLIT_FACTORY.address)}</span>
            <ExternalLink className="size-3" />
          </a>
        </div>
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
      </header>

      <main className="mx-auto max-w-md px-4 py-10 space-y-5">

        {/* Hero empty state — no split selected */}
        {!selectedId && (
          <div className="rounded-3xl p-8 text-center" style={{
            background: 'linear-gradient(135deg, rgba(245,200,66,0.07) 0%, rgba(255,255,255,0.02) 100%)',
            border: '1px solid rgba(245,200,66,0.14)',
            boxShadow: '0 8px 40px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.04)',
          }}>
            <div className="size-14 rounded-2xl flex items-center justify-center mx-auto mb-5" style={{
              background: 'rgba(245,200,66,0.10)',
              border: '1px solid rgba(245,200,66,0.20)',
              boxShadow: '0 0 28px rgba(245,200,66,0.08)',
            }}>
              <GitBranch className="size-6" style={{ color: 'var(--accent)' }} />
            </div>
            <h1 className="display text-2xl font-bold mb-2" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>
              Payment Splitter
            </h1>
            <p className="text-sm leading-relaxed mb-7" style={{ color: 'var(--muted)' }}>
              Create a split, add recipients with percentage shares,<br className="hidden sm:block" />
              send USDC, and distribute in one click.
            </p>
            <button
              onClick={() => setCreateOpen(true)}
              className="inline-flex items-center gap-2 rounded-2xl px-6 py-3.5 text-sm font-semibold transition-all active:scale-[0.98]"
              style={{
                background: 'var(--accent)',
                color: '#0c0c0c',
                boxShadow: '0 4px 28px rgba(245,200,66,0.28)',
              }}
            >
              <Plus className="size-4" />
              Create New Split
            </button>
            {!isConnected && (
              <p className="mt-4 text-xs" style={{ color: 'var(--subtle)' }}>
                Connect your wallet to create and manage splits
              </p>
            )}
          </div>
        )}

        {/* Selected split detail */}
        {selectedId !== null && (
          <div className="space-y-4">
            {/* Back + split header */}
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
              <div className="flex items-center gap-2">
                <div className="text-right">
                  <p className="display text-sm font-bold leading-tight" style={{ color: getSplitTitle(selectedId) ? '#E8B84B' : 'var(--ink)', letterSpacing: '-0.02em' }}>
                    {splitLabel(selectedId)}
                  </p>
                  {getSplitTitle(selectedId) && (
                    <p className="text-xs tabular-nums" style={{ color: 'var(--subtle)' }}>
                      Split #{selectedId.toString()}
                    </p>
                  )}
                </div>
                <button
                  onClick={() => setCreateOpen(true)}
                  className="flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition-all"
                  style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)', boxShadow: '0 0 0 1px rgba(245,200,66,0.20)' }}
                >
                  <Plus className="size-3" /> New
                </button>
              </div>
            </div>

            <SplitCard splitId={selectedId} />
          </div>
        )}

        {/* Feature strip — only visible on home state */}
        {!selectedId && (
          <div className="grid grid-cols-3 gap-3">
            {([
              {
                icon: <Users className="size-4" style={{ color: 'var(--accent)' }} />,
                label: 'Custom splits',
                body: 'Name your split, set recipients and exact percentage shares.',
              },
              {
                icon: <Wallet className="size-4" style={{ color: 'var(--accent)' }} />,
                label: 'Deposit USDC',
                body: 'Fund any split directly from your connected wallet.',
              },
              {
                icon: <Zap className="size-4" style={{ color: 'var(--accent)' }} />,
                label: 'One-click payout',
                body: 'Distribute the full balance to all recipients instantly.',
              },
            ] as { icon: React.ReactNode; label: string; body: string }[]).map(({ icon, label, body }) => (
              <div
                key={label}
                className="rounded-2xl p-4 flex flex-col gap-2.5"
                style={{
                  background: 'rgba(255,255,255,0.03)',
                  border: '1px solid rgba(245,200,66,0.09)',
                }}
              >
                <div
                  className="size-8 rounded-xl flex items-center justify-center shrink-0"
                  style={{ background: 'rgba(245,200,66,0.09)' }}
                >
                  {icon}
                </div>
                <div>
                  <p className="text-xs font-semibold mb-1" style={{ color: 'var(--ink)' }}>
                    {label}
                  </p>
                  <p className="text-xs leading-relaxed" style={{ color: 'var(--muted)', fontSize: '0.7rem' }}>
                    {body}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Splits sidebar — your splits + jump input */}
        {isConnected && (
          <SplitSelector selected={selectedId} onSelect={setSelectedId} onDeselect={() => setSelectedId(null)} />
        )}

        {/* Footer */}
        <div className="pt-2 pb-4 text-center">
          <p className="text-xs" style={{ color: 'var(--subtle)', opacity: 0.5 }}>
            Payment Splitter
          </p>
        </div>
      </main>

      {/* Create sheet */}
      <CreateSplitSheet open={createOpen} onClose={() => setCreateOpen(false)} onCreated={handleCreated} />
    </div>
  )
}
