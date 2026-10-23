# Payment Splitter

A minimal, production-quality USDC payment splitter. Anyone can create a split, assign recipients
with percentage shares, deposit USDC, and trigger a single **Distribute** action that pays every
recipient proportionally.

## What it does

- Anyone can create a split with up to 20 recipients and basis-point shares that total 100 %.
- Each split has its own isolated USDC balance tracked on-chain.
- Anyone can deposit USDC into any split and trigger distribution.
- The split creator can update recipients at any time.
- Rounding dust and failed transfers (e.g. blocklisted addresses) accrue in `pendingCreatorDust`
  and are recoverable via `rescueDust()`.

---

## Deployed contracts

| Network      | Address                                        | Explorer |
|--------------|------------------------------------------------|----------|
| Arc Testnet  | `0x20b1f718b7a612f605414bc47c5a2abdde1659cc`   | [ArcScan](https://explorer.testnet.arc.io/address/0x20b1f718b7a612f605414bc47c5a2abdde1659cc) |
| Arc Mainnet  | _0x9336ef11392Db07873cca919EeD8A4C6Cc1bB881_ | — | [https://explorer.arc.io]

USDC on Arc Testnet: `0x3600000000000000000000000000000000000000`
USDC on Arc Mainnet: `0x3600000000000000000000000000000000000000`
(verify both addresses at [developers.circle.com](https://developers.circle.com/stablecoins/usdc-on-test-networks) before use)

---

## Smart contract

Source: `contracts/SplitFactory.sol`

### Functions

| Function | Access | Description |
|----------|--------|-------------|
| `createSplit(address[], uint96[])` | Anyone | Create a new split; returns its `splitId` |
| `updateSplit(uint256, address[], uint96[])` | Creator only | Replace recipients for an existing split |
| `deposit(uint256 splitId, uint256 amount)` | Anyone | Pull USDC into a split (requires prior ERC-20 approval) |
| `distribute(uint256 splitId)` | Anyone | Pay out the full balance proportionally |
| `rescueDust(uint256 splitId)` | Creator only | Recover dust that couldn't be sent |
| `getSplit(uint256)` | View | Returns creator, balance, totalDistributed, recipientCount |
| `getRecipients(uint256)` | View | Returns recipient addresses and bps shares |

### Events

| Event | Emitted when |
|-------|-------------|
| `SplitCreated(splitId, creator)` | A new split is created |
| `SplitUpdated(splitId)` | Recipients are updated |
| `Deposited(splitId, sender, amount)` | USDC deposited into a split |
| `Distributed(splitId, totalAmount, recipientCount)` | Distribute called |
| `DustRescued(splitId, amount)` | Creator rescues pending dust |

### Custom errors

`Unauthorized` · `ZeroAddress` · `InvalidSplit` · `SplitNotFound` · `NoBalance` · `NoPendingDust` · `ZeroAmount`

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) — `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- [Bun](https://bun.sh/) — `curl -fsSL https://bun.sh/install | bash`
- A wallet with USDC (testnet or mainnet depending on target)

### Install dependencies

```bash
bun install
```

### Run tests

```bash
forge test -v
```

61 tests covering: happy paths, dust handling, all revert paths, access control, multiple
independent splits, fuzz (conservation of funds), and invariants.

### Build contracts

```bash
forge build
```

### Run UI locally

```bash
bun run dev
```

Open `http://localhost:5173`.

### Testing on Arc Testnet

1. Connect a wallet in the app.
2. Use the **Get test USDC** button in the Arc Studio sidebar.
3. Click **Create New Split**, enter recipient addresses and percentages (must total 100 %), confirm.
4. On the split page, enter an amount in the Send panel and click **Deposit USDC**.
5. Click **Distribute** to pay out the balance.

---

## Mainnet Deployment

> **WARNING — read before proceeding.**
> Mainnet transactions use real USDC and are irreversible. A mistake can result in permanent loss
> of funds. Complete all steps on testnet first, obtain an independent professional audit, and
> verify every address and value carefully before signing any mainnet transaction.

### 1. Prerequisites

- Foundry installed (see above).
- A wallet funded with Arc Mainnet ETH or USDC for gas.
  Arc uses USDC as the native gas token, so you need USDC in your deployer wallet.
- Your deployer private key stored in an environment variable — **never paste it into a file**.

  ```bash
  export DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
  ```

- Arc Mainnet RPC URL. Add it to `foundry.toml` under `[rpc_endpoints]`:

  ```toml
  arc = "https://rpc.arc.io"
  ```

  Confirm the current RPC URL at [docs.arc.io](https://docs.arc.io) before use.

### 2. Deploy the contract to Arc Mainnet

Arc Mainnet USDC address: `0x3600000000000000000000000000000000000000`
Verify this address at [developers.circle.com](https://developers.circle.com) before deploying.

```bash
forge create contracts/SplitFactory.sol:SplitFactory \
  --rpc-url arc \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args 0x3600000000000000000000000000000000000000 \
  --verify
```

`--verify` submits source code to the Arc explorer for public verification. If verification is
not supported on Arc Mainnet yet, omit that flag and verify manually later.

The command prints a `Deployed to:` address. Copy it — you need it in the next step.

### 3. Update the frontend with the mainnet contract address

Open `src/contract.ts` and replace the testnet address with your deployed mainnet address:

```ts
// src/contract.ts
export const SPLIT_FACTORY = {
  address: '0xYOUR_MAINNET_CONTRACT_ADDRESS' as const,   // <-- replace this
  abi: artifact.abi,
} as const

// Replace with Arc Mainnet USDC address
export const ARC_MAINNET_USDC = '0x3600000000000000000000000000000000000000' as const
```

Also update every reference to `ARC_TESTNET_USDC` and `ARC_TESTNET_ID` in
`src/components/SplitCard.tsx` to use the mainnet constants.

### 4. Switch the frontend to Arc Mainnet

Open `src/config.ts` and add Arc Mainnet alongside (or instead of) the testnet:

```ts
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
```

Check [viem.sh/docs/chains](https://viem.sh/docs/chains/introduction) to confirm the exact
import path and chain ID for Arc Mainnet before building.

### 5. Rebuild and redeploy the frontend

```bash
bun run build
```

Then deploy the `dist/` folder to your hosting provider (Netlify, Vercel, etc.).

---

## Important warnings about mainnet

1. **Real USDC, real losses.** Every transaction on mainnet moves real money. There is no undo.
2. **Audit before launch.** The contract passed an internal security review but has not had a
   paid professional audit. Do not hold significant funds in it without one.
3. **Verify all addresses.** Double-check the USDC contract address and your deployed contract
   address on the explorer before any deposits.
4. **Test the full flow on testnet first.** Create a split, deposit, and distribute on Arc Testnet
   until you are confident everything works as expected.
5. **Guard your deployer key.** Never commit your private key to version control or share it.
   Use hardware wallets for mainnet deployments where possible.
6. **Keep the contract address in AGENTS.md.** Once deployed, record the mainnet address so all
   future changes reference the correct contract.

---

## Architecture

| File | Purpose |
|------|---------|
| `contracts/SplitFactory.sol` | Core Solidity contract |
| `contracts/test/SplitFactory.t.sol` | Foundry unit + fuzz + invariant tests |
| `src/contract.ts` | Contract address + ABI |
| `src/config.ts` | wagmi chain + transport config |
| `src/components/SplitCard.tsx` | Split detail: balance, recipients, distribute, deposit |
| `src/components/CreateSplitSheet.tsx` | Create split bottom sheet |
| `src/components/SplitSelector.tsx` | Browse and select splits |
| `src/utils.ts` | Formatting helpers |

## Security review summary

The contract was reviewed across three audit rounds before testnet deployment:

1. `owner` and `usdc` made `immutable`.
2. `distribute()` reverts with `SplitNotConfigured` when called with no recipients.
3. Per-recipient ERC-20 transfers wrapped in `try/catch` — a single blocklisted address cannot
   brick the whole distribution.
4. Creator dust sweep also `try/catch` — failures accumulate in `pendingCreatorDust` and are
   recoverable via `rescueDust()`.

This review covers common vulnerability classes but is **not a substitute for a professional
audit** before deploying to mainnet or holding significant user funds.
