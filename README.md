# Payment Splitter

A USDC payment splitter on Arc and Base. Anyone can create a named split, assign recipients with percentage
shares, deposit USDC, and trigger a single **Distribute** that pays every recipient proportionally. A small,
adjustable protocol fee is taken on deposits and bridges. Users earn STR points and can bridge USDC between
Arc and Base.

Built with [Arc Studio](https://studio.arc.io)

## What it does

- Create a split with up to 20 recipients whose shares total 100%. Each split has its own USDC balance.
  Anyone can deposit into any split and anyone can distribute it.
- Every split has a required **name**, and recipients can have a **name or tag**. Both are stored on-chain, so they
  show on any device. A split without a name shows as "Split #ID"; a recipient without a tag shows just the address.
- A **protocol fee** (default 0.5%, never above 5%) is taken on each deposit and each bridge and sent to a fee
  recipient. The screen shows the exact fee before you confirm. The contract owner can change the fee and the
  fee recipient from the owner panel.
- Four pages with a bottom navigation bar: **Home**, **Bridge**, **Points**, **Leaderboard**. An Arc / Base switcher
  moves between the two networks, which have separate splits, balances and fee settings.
- **Bridge USDC** between Arc and Base with CCTP Fast Transfer. It shows the platform fee, the network fee, the
  amount you receive and live progress. One bridge at a time per wallet.
- **STR points** for deposits, distributions and bridges by amount, plus a daily check-in:

  | Amount (USDC) | STR | Daily max once reached |
  |---|---|---|
  | under 1 | 0 | 50 |
  | 1 to 9.99 | +5 | 50 |
  | 10 to 49.99 | +25 | 75 |
  | 50 to 99.99 | +50 | 100 |
  | 100 to 249.99 | +75 | 150 |
  | 250 to 999.99 | +100 | 200 |
  | 1,000 and above | +150 | 600 |

  The daily max (deposits, distributions and bridges combined) starts at 50 and rises to the highest tier reached
  that day. Deposits and bridges count by the amount sent; a distribution counts by the split's balance after the
  fee. Daily check-in is +5, with +25 on the 7th consecutive day (then the streak resets; missing a day also
  resets it). A "day" is a UTC calendar day (resets at 00:00 UTC). The global **Leaderboard** ranks wallets by
  total STR across both networks, with gold, silver and bronze medals for the top three.
- If a recipient cannot receive USDC (for example a blocklisted address), their share is kept for them to claim
  later. It is never given to anyone else.

## The contracts

Four contracts are deployed on **each** network (eight in total). Deploy `SplitFactory` first; the other three
need its address.

| Contract | File | Purpose | Constructor arguments (in order) |
|---|---|---|---|
| `SplitFactory` | `contracts/SplitFactory.sol` | Splits, balances, protocol fee, owner | `address _usdc`, `address _owner`, `address _feeRecipient`, `uint16 _feeBps` |
| `StrPoints` | `contracts/StrPoints.sol` | STR points, check-in, leaderboard data, CCTP bridge | `address _factory`, `address _usdc`, `uint256 _dayLength`, `address _tokenMessenger`, `uint32 _destinationDomain` |
| `SplitNames` | `contracts/SplitNames.sol` | On-chain split names | `address _factory` |
| `RecipientLabels` | `contracts/RecipientLabels.sol` | On-chain recipient names/tags | `address _factory` |

Notes on the contracts:

- `SplitFactory`: ownership uses a two-step transfer and cannot be renounced. `_feeBps` is capped at 500 (5%).
  Deposits revert if the recipient list changed since the depositor looked. A recipient who cannot receive USDC
  keeps a claimable balance. Recipients cannot be the contract itself, the USDC token or any address below `0x10000`.
- `StrPoints`: deposits, distributions and bridges made in the app go through it, so points are only awarded when
  the action succeeds. Because USDC is approved to this contract, the first deposit on each network asks for a new
  approval. The bridge fee is read live from the `SplitFactory`. `_dayLength` is `86400` (24 hours). Each
  deployment bridges to its paired chain (`_destinationDomain`).
- Names and tags can only be set by the split's creator.
- Known limits: if the fee recipient becomes blocklisted, deposits and bridges that carry a fee fail until the
  owner changes the recipient or sets the fee to 0. The platform fee and STR are credited when a bridge's burn
  confirms, because a contract cannot verify the destination chain. Only use normal wallet addresses as
  recipients. The contracts have had automated security reviews and unit, fuzz and invariant tests, but **no
  professional audit**.

## Testnet deployments (reference)

| Contract | Arc Testnet (chain 5042002) | Base Sepolia (chain 84532) |
|---|---|---|
| `SplitFactory` | `0x1f311ff4b12cb107309b18f92bdaa63c4ab08e18` | `0xc0f3e95fb51fa186afadcefe045274e19096984f` |
| `StrPoints` | `0x9b534831098c6b1a9d5880662d8704d99af23c0a` | `0xa5d218ab623372d6ac54c84bb3db15ac7363015b` |
| `SplitNames` | `0x8b3a33056c27b3eba7c2bfb34e433f06edec6e00` | `0xaeba323c4d6bbf225e260be22cb7fd59540fa2dd` |
| `RecipientLabels` | `0x8ef699dc26669979ab650f7b40ad17855b1fd649` | `0x66b74ecd715e67ba0426bfa309ff9a3975afc426` |

Testnet settings: fee 50 bps (0.5%), `_dayLength` 86400. Explorers: `https://explorer.testnet.arc.io`,
`https://sepolia.basescan.org`.

## Development

Prerequisites: [Foundry](https://book.getfoundry.sh/getting-started/installation) and [Bun](https://bun.sh/).

```bash
bun install
bun run dev            # app at http://localhost:5173
bun run build          # production build
forge build            # compile contracts
forge test             # run contract tests (needs forge-std in lib/)
bun run abi:sync       # after changing a contract: copy ABIs from forge's output into src/abi/
bun run check          # lint and typecheck
```

Environment variables: None.

Everything that differs between networks (chain IDs, USDC addresses, CCTP domains, the contract addresses and the
status-API URL) lives in one file, `src/network.ts`. Contract ABIs are committed in `src/abi/`, so the app builds
without compiling the contracts.

---

# Mainnet deployment guide

> **Warning:** Transactions on mainnet involve real funds and, once submitted, are irreversible. Arc Studio may
> generate or edit code or configuration that references mainnet, but Arc Studio does not deploy to, transact on,
> sign for, fund, or otherwise interact with mainnet on your behalf. Any code used for mainnet must be
> independently reviewed, tested, validated, deployed, and operated by you outside of Arc Studio. You are solely
> responsible for any losses, errors, or other consequences resulting from your use of any code, configuration, or
> output generated or edited through Arc Studio in connection with mainnet. Before proceeding, you should first use
> testnet, obtain an independent professional audit, and carefully review all wallet addresses, contract addresses,
> chain settings, permissions, and other configuration details. Only continue to mainnet after you have completed
> your independent review and have determined that you want to proceed.

This guide moves the working testnet app into your existing mainnet repository,
`github.com/simon4040/Payment-Splitter`, and deploys it on **Arc Mainnet and Base Mainnet**.

## What is different from your current mainnet repo

| | Your mainnet repo today (`fba10ee`) | After this guide |
|---|---|---|
| Networks | Arc Mainnet only | Arc Mainnet and Base Mainnet |
| Contracts | 1 (`SplitFactory`, no fee) at `0x9336ef11392Db07873cca919EeD8A4C6Cc1bB881` | 8 (4 per network) |
| Fee, names, tags | none; titles in browser only | adjustable fee; names and tags on-chain |
| Points, leaderboard, bridge | none | included |
| Frontend config | `src/contract.ts` with one address | `src/network.ts` with 8 addresses |

The new `SplitFactory` has a different interface and cannot replace the old one in place. The 2 splits on your old
contract stay there and will not appear in the new app (see step 9). Points, names, tags and the leaderboard
start empty.

The complete file-by-file list is in [`docs/mainnet-files.md`](docs/mainnet-files.md).

## Before you start

- [ ] You have run the full flow on testnet (done) and read the warning above.
- [ ] You have arranged an independent professional audit of the four contracts.
- [ ] **Owner wallet**: controls the protocol fee and fee recipient on that network. Use a hardware wallet or
      multisig. It can be the same on both networks.
- [ ] **Fee recipient**: where fees are paid. It must be able to receive USDC (not blocklisted).
- [ ] **Deployer wallet** (can be the owner or a throwaway): needs **USDC for gas on Arc** (USDC is Arc's gas token)
      and **ETH for gas on Base**.
- [ ] Foundry and Bun installed; your repo checked out; the deployer key available as an environment variable
      (never saved in a file).

## Step 1: Copy the new files into your repo

From this project's folder:

```bash
bash mainnet/apply-to-repo.sh /path/to/Payment-Splitter
```

This copies 57 shared files plus the 4 mainnet-only files, and deletes nothing. It does not touch your
`index.html`, `foundry.toml`, `AGENTS.md`, `.gitignore`, `public/` or `bun.lock`.

Then, inside your repo:

```bash
cd /path/to/Payment-Splitter
bun install
forge install foundry-rs/forge-std   # only if lib/forge-std is missing
forge test                           # all suites should pass before you deploy anything
```

## Step 2: Constants for each network

| | Arc Mainnet | Base Mainnet |
|---|---|---|
| Chain ID | `5042` | `8453` |
| RPC (public) | `https://rpc.mainnet.arc.io` | `https://mainnet.base.org` |
| Explorer | `https://explorer.arc.io` | `https://basescan.org` |
| USDC | `0x3600000000000000000000000000000000000000` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| CCTP domain | `26` | `6` |
| CCTP `TokenMessengerV2` | `0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d` | `0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d` |
| `_destinationDomain` for `StrPoints` | `6` (Base) | `26` (Arc) |

Your own values: `OWNER`, `FEE_RECIPIENT`, and the fee `50` (0.5%; maximum 500). `_dayLength` is `86400`.

Check these against Circle's published docs before you deploy; the public RPC URLs are rate-limited, so use your
own RPC provider if a deployment times out.

## Step 3: Deploy the contracts

Deployment order, per network: **`SplitFactory` first**, then `StrPoints`, `SplitNames`, `RecipientLabels`
(each needs the `SplitFactory` address). The two networks are independent; do Arc first, then Base.

Set your values (the private key stays in your shell, not in a file):

```bash
export PRIVATE_KEY=0x...                  # deployer key
export OWNER=0x...                        # owner wallet
export FEE_RECIPIENT=0x...                # fee recipient
export TOKEN_MESSENGER=0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d
```

### Arc Mainnet

```bash
export RPC=https://rpc.mainnet.arc.io
export USDC=0x3600000000000000000000000000000000000000

# 1. SplitFactory(usdc, owner, feeRecipient, feeBps)
forge create contracts/SplitFactory.sol:SplitFactory --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $USDC $OWNER $FEE_RECIPIENT 50
export ARC_FACTORY=0x...                  # the "Deployed to:" address printed above

# 2. StrPoints(factory, usdc, dayLength, tokenMessenger, destinationDomain = Base's 6)
forge create contracts/StrPoints.sol:StrPoints --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $ARC_FACTORY $USDC 86400 $TOKEN_MESSENGER 6
export ARC_POINTS=0x...

# 3. SplitNames(factory)
forge create contracts/SplitNames.sol:SplitNames --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $ARC_FACTORY
export ARC_NAMES=0x...

# 4. RecipientLabels(factory)
forge create contracts/RecipientLabels.sol:RecipientLabels --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $ARC_FACTORY
export ARC_LABELS=0x...
```

### Base Mainnet

```bash
export RPC=https://mainnet.base.org
export USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913

# 1. SplitFactory(usdc, owner, feeRecipient, feeBps)
forge create contracts/SplitFactory.sol:SplitFactory --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $USDC $OWNER $FEE_RECIPIENT 50
export BASE_FACTORY=0x...

# 2. StrPoints(factory, usdc, dayLength, tokenMessenger, destinationDomain = Arc's 26)
forge create contracts/StrPoints.sol:StrPoints --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $BASE_FACTORY $USDC 86400 $TOKEN_MESSENGER 26
export BASE_POINTS=0x...

# 3. SplitNames(factory)
forge create contracts/SplitNames.sol:SplitNames --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $BASE_FACTORY
export BASE_NAMES=0x...

# 4. RecipientLabels(factory)
forge create contracts/RecipientLabels.sol:RecipientLabels --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $BASE_FACTORY
export BASE_LABELS=0x...
```

Constructor values cannot be changed after deployment. If one is wrong, deploy that contract again (and anything
that points to it).

## Step 4: Verify what you deployed

Run these before anyone deposits. Expected values are in the comments.

```bash
# Arc
export RPC=https://rpc.mainnet.arc.io
cast call $ARC_FACTORY "owner()(address)"        --rpc-url $RPC   # your OWNER
cast call $ARC_FACTORY "feeBps()(uint16)"        --rpc-url $RPC   # 50
cast call $ARC_FACTORY "feeRecipient()(address)" --rpc-url $RPC   # your FEE_RECIPIENT
cast call $ARC_POINTS  "factory()(address)"      --rpc-url $RPC   # $ARC_FACTORY
cast call $ARC_POINTS  "dayLength()(uint256)"    --rpc-url $RPC   # 86400
cast call $ARC_POINTS  "tokenMessenger()(address)"  --rpc-url $RPC   # 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d
cast call $ARC_POINTS  "destinationDomain()(uint32)" --rpc-url $RPC  # 6
cast call $ARC_NAMES   "factory()(address)"      --rpc-url $RPC   # $ARC_FACTORY
cast call $ARC_LABELS  "factory()(address)"      --rpc-url $RPC   # $ARC_FACTORY

# Base: same calls with the BASE_* addresses and RPC=https://mainnet.base.org.
# Expected differences: destinationDomain() is 26.
```

Also open each address on the explorer and confirm it is the contract you expect.

## Step 5: Put the addresses in the frontend

Open **`src/network.ts`** in your repo. It is the only file with addresses. Replace the eight placeholder
addresses (`0x0000…`) with the ones you deployed. The finished file looks like this:

```ts
export const IS_MAINNET = true
export const IRIS_API = 'https://iris-api.circle.com'   // mainnet status/fee API

export const NETWORK: Record<'arc' | 'base', ChainDeployment> = {
  arc: {
    id: 5042,                                                    // Arc Mainnet
    usdc: '0x3600000000000000000000000000000000000000',
    cctpDomain: 26,
    factory: '<ARC_FACTORY>',
    points: '<ARC_POINTS>',
    names: '<ARC_NAMES>',
    labels: '<ARC_LABELS>',
  },
  base: {
    id: 8453,                                                    // Base Mainnet
    usdc: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    cctpDomain: 6,
    factory: '<BASE_FACTORY>',
    points: '<BASE_POINTS>',
    names: '<BASE_NAMES>',
    labels: '<BASE_LABELS>',
  },
}
```

(Leave the `ChainDeployment` interface at the top of the file as it is.) Do not change `id`, `usdc`,
`cctpDomain` or `IRIS_API`.

The other mainnet-specific file, **`src/config.ts`**, is already correct after step 1. It sets up the wallet
connection for Arc Mainnet, Base Mainnet and Ethereum (for ENS names):

```ts
import { arc, base } from 'viem/chains'
export const config = createConfig({
  chains: [arc, base, mainnet],
  connectors: [injected()],
  transports: { [arc.id]: http(), [base.id]: http(), [mainnet.id]: http() },
})
```

The app refuses to start, and `bun run build` refuses to build, while any address is still a placeholder, so a
half-configured version can never be published.

## Step 6: Build and try it locally

```bash
bun run build          # runs the address check first, then the production build
bun run dev            # open http://localhost:5173 and connect your wallet
```

Confirm that the Arc / Base switcher works, and that connecting the **owner** wallet shows the owner panel at the
bottom of Home.

## Step 7: Publish to GitHub and deploy to Vercel

1. Commit and push:

   ```bash
   git add -A
   git commit -m "Mainnet: Arc + Base, fee, points, bridge, on-chain names and tags"
   git push
   ```

2. In Vercel: **Add New, Project**, import `simon4040/Payment-Splitter`.
3. Settings:
   - Framework Preset: **Vite**
   - Install Command: `bun install`
   - Build Command: `bun run build`
   - Output Directory: `dist`
   - Environment Variables: **none**
4. Click **Deploy**. If the build stops with "Mainnet configuration is incomplete", an address in
   `src/network.ts` is still a placeholder.
5. Open the deployment URL and run step 8 before you share it.

## Step 8: Smoke test with small amounts

On each network, with a wallet holding a few USDC:

1. Create a split (two recipients you control) with a name and tags, then reload the page: name and tags remain.
2. Deposit 1 USDC. The preview should show 0.995 to the split and 0.005 fee. Confirm the fee recipient received
   0.005 USDC and the split balance is 0.995.
3. Press Distribute. Both recipients are paid and the balance returns to 0.
4. Check in on the Points page. Confirm the STR amounts match the tier table.
5. Connect the **owner** wallet and use the owner panel to change the fee to a new value and back (this is the
   only way to confirm that you are the owner).
6. Bridge 2 USDC Arc to Base and Base to Arc. Confirm the amount you receive matches the "You receive" line and
   that the tracker reaches "Received". Network fees are quoted live and are real money.

## Step 9: After launch

- Add the eight mainnet addresses to the table in this README (under "Mainnet deployments") and to `AGENTS.md`.
- Keep your previous deployment (commit `fba10ee`) available at its own URL if people still have funds in the
  2 old splits. The new app does not read the old contract.
- Optional: in `index.html`, change the description from "on Arc Mainnet" to "on Arc and Base".
- Optional clean-up of leftover files is listed in [`docs/mainnet-files.md`](docs/mainnet-files.md).

## Mainnet deployments

| Contract | Arc Mainnet | Base Mainnet |
|---|---|---|
| `SplitFactory` | _fill in after deploying_ | _fill in after deploying_ |
| `StrPoints` | _fill in after deploying_ | _fill in after deploying_ |
| `SplitNames` | _fill in after deploying_ | _fill in after deploying_ |
| `RecipientLabels` | _fill in after deploying_ | _fill in after deploying_ |

## Mainnet warnings

1. Every transaction moves real USDC and cannot be undone.
2. Get an independent professional audit before holding significant funds.
3. Check every address on the explorer before depositing. Constructor values cannot be changed afterwards.
4. The owner wallet controls the protocol fee (up to 5%) and where fees go. Protect it.
5. Never commit your private key or paste it into a file. Use a hardware wallet where possible.
6. Bridges are real transfers: always test with a small amount first.

---

## Project layout

| Path | Purpose |
|------|---------|
| `contracts/` | `SplitFactory.sol`, `StrPoints.sol`, `SplitNames.sol`, `RecipientLabels.sol`, plus tests in `contracts/test/` |
| `src/network.ts` | Chain IDs, USDC, CCTP domains, contract addresses, status-API URL (the only file that differs between testnet and mainnet, with `src/config.ts`) |
| `src/contract.ts` | Builds the per-network setup from `src/network.ts` and the ABIs |
| `src/abi/` | Committed contract ABIs (`bun run abi:sync` refreshes them) |
| `src/config.ts` | Wallet and chain setup |
| `src/bridge.ts` | Bridge fee quote, transfer status and in-progress tracking |
| `src/App.tsx` | Page shell and tab navigation |
| `src/components/` | Pages and widgets: Home, Bridge, Points, Leaderboard, split page, create form, owner panel |
| `src/hooks/` | Reads for points, names, tags, fees and split lists |
| `mainnet/` | The mainnet-only files and the copy script used in step 1 |
| `docs/mainnet-files.md` | The complete file-by-file comparison with your mainnet repo |
