import { useState, type ReactNode } from 'react'
import { CHAINS, type ChainKey } from '@/contract'
import { ChainContext } from '@/hooks/useChain'

const STORAGE_KEY = 'selected-chain'

function readInitial(): ChainKey {
  try {
    const v = localStorage.getItem(STORAGE_KEY)
    if (v === 'arc' || v === 'base') return v
  } catch { /* storage unavailable */ }
  return 'arc'
}

export function ChainProvider({ children }: { children: ReactNode }) {
  const [key, setKey] = useState<ChainKey>(readInitial)

  const setChainKey = (next: ChainKey) => {
    setKey(next)
    try { localStorage.setItem(STORAGE_KEY, next) } catch { /* silent */ }
  }

  return (
    <ChainContext.Provider value={{ chain: CHAINS[key], setChainKey }}>
      {children}
    </ChainContext.Provider>
  )
}
