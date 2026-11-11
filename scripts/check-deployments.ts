/**
 * Runs automatically before `bun run build` (see "prebuild" in package.json). Stops the build if
 * src/network.ts still has placeholder addresses or is not the mainnet file, so a half-configured
 * app can never be published.
 */
import { IS_MAINNET, NETWORK } from '../src/network'

const ZERO = '0x0000000000000000000000000000000000000000'
const problems: string[] = []

if (!IS_MAINNET) problems.push('src/network.ts is not the mainnet version (IS_MAINNET is false)')
if (NETWORK.arc.id !== 5042) problems.push(`Arc chain id should be 5042, found ${NETWORK.arc.id}`)
if (NETWORK.base.id !== 8453) problems.push(`Base chain id should be 8453, found ${NETWORK.base.id}`)

for (const chain of ['arc', 'base'] as const) {
  for (const field of ['factory', 'points', 'names', 'labels'] as const) {
    const value = NETWORK[chain][field]
    if (!/^0x[0-9a-fA-F]{40}$/.test(value)) problems.push(`${chain}.${field} is not a valid address: ${value}`)
    else if (value.toLowerCase() === ZERO) problems.push(`${chain}.${field} is still the zero-address placeholder`)
  }
}

if (problems.length > 0) {
  console.error('\nMainnet configuration is incomplete:\n')
  for (const p of problems) console.error(`  - ${p}`)
  console.error('\nFill in src/network.ts (see README, "Mainnet deployment guide"), then build again.\n')
  process.exit(1)
}
console.log('Mainnet configuration OK: all 8 contract addresses are set.')
