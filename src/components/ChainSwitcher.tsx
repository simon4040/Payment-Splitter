import { NetworkArc, NetworkBase } from '@web3icons/react'
import { CHAINS, CHAIN_KEYS, type ChainKey } from '@/contract'
import { useChainSwitch } from '@/hooks/useChain'

/** Official network logos (vector, so they stay sharp at any pixel density). */
function ChainLogo({ chainKey, active }: { chainKey: ChainKey; active: boolean }) {
  const Logo = chainKey === 'arc' ? NetworkArc : NetworkBase
  return (
    <span
      aria-hidden
      className="flex size-5 shrink-0 items-center justify-center overflow-hidden rounded-md"
      style={{ boxShadow: active ? '0 0 0 1.5px rgba(12,12,12,0.22)' : '0 0 0 1px rgba(255,255,255,0.14)' }}
    >
      <Logo variant="background" size={20} />
    </span>
  )
}

/** Segmented Arc / Base control. */
export function ChainSwitcher({ onChange }: { onChange?: (key: ChainKey) => void }) {
  const { chain, setChainKey } = useChainSwitch()

  return (
    <div
      role="tablist"
      aria-label="Network"
      className="mx-auto flex w-fit items-center gap-1 rounded-2xl p-1"
      style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(245,200,66,0.12)',
      }}
    >
      {CHAIN_KEYS.map(key => {
        const active = chain.key === key
        return (
          <button
            key={key}
            role="tab"
            aria-selected={active}
            onClick={() => {
              if (active) return
              setChainKey(key)
              onChange?.(key)
            }}
            className="flex items-center justify-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition-all active:scale-[0.98]"
            style={{
              background: active ? 'var(--accent)' : 'transparent',
              color: active ? '#0c0c0c' : 'var(--muted)',
              boxShadow: active ? '0 2px 16px rgba(245,200,66,0.22)' : 'none',
              minWidth: '6.25rem',
            }}
          >
            <ChainLogo chainKey={key} active={active} />
            {CHAINS[key].label}
          </button>
        )
      })}
    </div>
  )
}
