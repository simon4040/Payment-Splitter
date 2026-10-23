/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { mainnet } from 'wagmi/chains'
import { arc } from 'viem/chains'          // Arc Mainnet chain definition
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'

registerChain(arc.id, arc.rpcUrls.default.http[0])

export const config = createConfig({
  chains: [arc, mainnet],
  connectors: [injected()],
  transports: {
    [arc.id]: http(),
    [mainnet.id]: http(),
  },
})