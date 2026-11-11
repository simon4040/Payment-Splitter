/**
 * Copies the ABIs of the four contracts from Foundry's build output into src/abi/*.json.
 * The app imports these committed files (contracts/out is git-ignored), so run this after
 * changing a contract:   forge build && bun run abi:sync
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const CONTRACTS = ['SplitFactory', 'StrPoints', 'SplitNames', 'RecipientLabels']

mkdirSync('src/abi', { recursive: true })
for (const name of CONTRACTS) {
  const artifact = JSON.parse(readFileSync(`contracts/out/${name}.sol/${name}.json`, 'utf8')) as { abi: unknown }
  writeFileSync(`src/abi/${name}.json`, JSON.stringify({ abi: artifact.abi }, null, 2) + '\n')
  console.log(`src/abi/${name}.json`)
}
