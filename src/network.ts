/**
 * MAINNET deployment: every chain id, token address, CCTP domain and contract address the app uses.
 * Nothing else in the app hardcodes a chain or an address.
 */

export const IS_MAINNET = true

/** Circle's CCTP status + fee API (mainnet). */
export const IRIS_API = 'https://iris-api.circle.com'

export interface ChainDeployment {
  /** EVM chain id. */
  id: number
  /** Official USDC token (6 decimals). */
  usdc: `0x${string}`
  /** Circle CCTP domain of this chain. */
  cctpDomain: number
  /** SplitFactory: splits, balances, protocol fee. */
  factory: `0x${string}`
  /** StrPoints: STR points, daily check-in, leaderboard, CCTP bridge. */
  points: `0x${string}`
  /** SplitNames: on-chain split names. */
  names: `0x${string}`
  /** RecipientLabels: on-chain recipient names/tags. */
  labels: `0x${string}`
}

export const NETWORK: Record<'arc' | 'base', ChainDeployment> = {
  arc: {
    id: 5042,
    usdc: '0x3600000000000000000000000000000000000000',
    cctpDomain: 26,
    factory: '0x5A3EDbcC6406D99dE36ee159B56C6a5Ceb22843A',
    points: '0xe86fD18d14e8104E6108894bA34887737d75e83f',
    names: '0x87A180c552c220Ad592e144Ad69980dC08Ac8204',
    labels: '0x99dCa7934A1d8ad4FB335c92FF078d14260285dc',
  },
  base: {
    id: 8453, // Base Mainnet
    usdc: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    cctpDomain: 6,
    factory: '0x9336ef11392Db07873cca919EeD8A4C6Cc1bB881',
    points: '0x5Ea945f5491C73978cce56924c4dc92b3b1c3A38',
    names: '0x06e879972f9b24FB258100E9B3A9FeA060Df77D9',
    labels: '0x948787C73cF74Fa25800b57fcbDCa95a516187f2', 
  },
}
