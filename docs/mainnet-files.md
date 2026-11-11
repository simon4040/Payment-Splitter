# Mainnet file inventory

Compared: this project (the working testnet app) against your mainnet repository
`simon4040/Payment-Splitter` at commit `fba10ee` ("Fix favicon reference").

Your mainnet repo is the original single-chain app: one `SplitFactory` on Arc Mainnet
(`0x9336ef11392Db07873cca919EeD8A4C6Cc1bB881`), with no protocol fee, points, names, tags, Base or bridge.
The testnet app is a four-contract system on two chains.

`bash mainnet/apply-to-repo.sh /path/to/Payment-Splitter` copies everything in sections 1 to 3 for you and
changes nothing else. Sections 4 and 5 are what it deliberately leaves alone.

## 1. New files to add (45)

These do not exist in your repo yet.

- `docs/mainnet-files.md`
- `contracts/RecipientLabels.sol`
- `contracts/SplitNames.sol`
- `contracts/StrPoints.sol`
- `contracts/test-helpers/MockBlocklistERC20.sol`
- `contracts/test-helpers/MockTokenMessengerV2.sol`
- `contracts/test/RecipientLabels.t.sol`
- `contracts/test/SplitFactory.Base.t.sol`
- `contracts/test/SplitFactory.Deferral.t.sol`
- `contracts/test/SplitFactory.Deposit.t.sol`
- `contracts/test/SplitFactory.Fuzz.t.sol`
- `contracts/test/SplitFactory.Invariant.t.sol`
- `contracts/test/SplitNames.t.sol`
- `contracts/test/StrPoints.Base.t.sol`
- `contracts/test/StrPoints.Bridge.t.sol`
- `contracts/test/StrPoints.BridgeFuzz.t.sol`
- `contracts/test/StrPoints.BridgePoints.t.sol`
- `contracts/test/StrPoints.Cap.t.sol`
- `contracts/test/StrPoints.CheckIn.t.sol`
- `contracts/test/StrPoints.Fuzz.t.sol`
- `contracts/test/StrPoints.FuzzActivity.t.sol`
- `contracts/test/StrPoints.Invariant.t.sol`
- `contracts/test/StrPoints.Tiers.t.sol`
- `contracts/test/StrPoints.t.sol`
- `scripts/sync-abis.ts`
- `src/abi/RecipientLabels.json`
- `src/abi/SplitNames.json`
- `src/abi/StrPoints.json`
- `src/bridge.ts`
- `src/components/BottomNav.tsx`
- `src/components/BridgePage.tsx`
- `src/components/ChainProvider.tsx`
- `src/components/ChainSwitcher.tsx`
- `src/components/FeeAdminPanel.tsx`
- `src/components/LeaderboardPage.tsx`
- `src/components/PointsPage.tsx`
- `src/components/RecipientTagsEditor.tsx`
- `src/components/SplitHeading.tsx`
- `src/components/StrNotice.tsx`
- `src/hooks/strTiers.ts`
- `src/hooks/useChain.ts`
- `src/hooks/useFeeConfig.ts`
- `src/hooks/usePoints.ts`
- `src/hooks/useRecipientLabels.ts`
- `src/hooks/useSplitName.ts`

## 2. Files to replace (12)

These exist in your repo and are replaced with the new version.

- `README.md`
- `contracts/SplitFactory.sol`
- `contracts/test/SplitFactory.t.sol`
- `src/App.tsx`
- `src/abi/SplitFactory.json`
- `src/components/CreateSplitSheet.tsx`
- `src/components/SplitCard.tsx`
- `src/components/SplitSelector.tsx`
- `src/contract.ts`
- `src/hooks/useSplitIds.ts`
- `src/hooks/useSplitTitle.ts`
- `src/utils.ts`

## 3. Mainnet-only files (from the `mainnet/` folder) (4)

The testnet project has its own versions of these four paths; the mainnet versions are the ones that go into your repo.

- `src/network.ts   (from mainnet/src/network.ts: chain IDs, USDC, CCTP domains, the 8 contract addresses, status API URL. NEW file)`
- `src/config.ts    (from mainnet/src/config.ts: wagmi chains Arc + Base + Ethereum for ENS. REPLACES your current file)`
- `scripts/check-deployments.ts (from mainnet/scripts/check-deployments.ts: stops the build while addresses are placeholders. NEW file)`
- `package.json     (from mainnet/package.json: same dependencies as yours, plus the `abi:sync` and `prebuild` scripts. REPLACES your file)`

## 4. Files in your repo that are kept as they are

The copy script never touches these:

- `index.html`: your SEO tags, social-card image and favicon. (Optional: its description says "on Arc Mainnet"; you may want "on Arc and Base".)
- `foundry.toml`: it has your `arc` and `arc_testnet` RPC aliases. The testnet project's file does not, so it must not overwrite yours.
- `AGENTS.md`: your project notes. Update it by hand after deploying (see README, step 9).
- `.gitignore`, `public/favicon.png`, `public/og-image.png`, `bun.lock` (dependencies are identical, so the lockfile stays valid).
- Already identical to the testnet project, no action needed (27 files): `.bun-version`, `.foundry-version`, `.oxlintrc.json`, `postcss.config.js`, `remappings.txt`, `tailwind.config.js`, `tsconfig.json`, `vite.config.ts`, `src/index.css`, `src/main.tsx`, `src/onchain-facts.ts`, `src/onchain-money.ts`, `src/onchain-wait.ts`, `src/tracing.ts`, `src/console-capture.ts`, `src/vite-env.d.ts`, `contracts/script/*`, `contracts/test-helpers/MockERC20.sol`, `scripts/check.sh`, the existing deploy helper scripts under `scripts/`, and the `.gitkeep` files.

## 5. Not copied, on purpose

- `lib/` (the Foundry test library, git-ignored in your repo). If your checkout does not have it, run `forge install foundry-rs/forge-std`.
- `node_modules/`, `dist/`, `contracts/out/`, `contracts/cache/`, `.env*`, `traces.jsonl`, `console.jsonl`.
- `contracts/contract-metadata/*.json` (records of testnet deployments made inside Arc Studio).

## 6. Optional clean-up in your repo

These are leftovers, safe to delete once you have copied the new files:

- `payment_splitter.zip`, `traces.jsonl`, `console.jsonl`
- `contracts/contract-metadata/PaymentSplitter.json` and `contracts/contract-metadata/SplitFactory.json` (old testnet records)

## 7. What changes for users

- The new `SplitFactory` is a different contract with a different ABI (deposits now carry a fee and a version number).
  It cannot be upgraded in place. The 2 splits on your existing mainnet `SplitFactory` stay on that contract and
  will not appear in the new app. To keep them usable, leave the previous deployment (commit `fba10ee`) running at its
  own address.
- Points, names, tags and the leaderboard start empty on mainnet.
