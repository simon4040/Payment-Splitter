/**
 * The chain the UI is currently showing (Arc or Base).
 * Every read, write, balance, split list and fee setting follows this value.
 */
import { createContext, useContext } from 'react'
import { CHAINS, type ChainKey, type ChainSetup } from '@/contract'

export interface ChainState {
  chain: ChainSetup
  setChainKey: (key: ChainKey) => void
}

export const ChainContext = createContext<ChainState>({
  chain: CHAINS.arc,
  setChainKey: () => {},
})

/** The active chain's setup: id, USDC address, factory address + ABI. */
export function useChain(): ChainSetup {
  return useContext(ChainContext).chain
}

export function useChainSwitch(): ChainState {
  return useContext(ChainContext)
}
