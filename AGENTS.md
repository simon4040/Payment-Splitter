# Payment Splitter

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

A multi-split USDC factory on Arc Testnet. Anyone can create their own payment split (recipients + basis-point shares totalling 10000). Each split has a unique ID and its own tracked balance. Creators can update recipients. Anyone can deposit USDC into any split via ERC-20 approval + deposit(). Anyone can call distribute() to pay out proportionally. Dust and failed transfers accumulate in pendingCreatorDust for the split creator to rescue.

## Deployed Contracts

| Contract | Address | Network | Explorer |
|----------|---------|---------|---------|
| SplitFactory | 0x20b1f718b7a612f605414bc47c5a2abdde1659cc | ARC-TESTNET | https://explorer.testnet.arc.io/address/0x20b1f718b7a612f605414bc47c5a2abdde1659cc |

- USDC: 0x3600000000000000000000000000000000000000 (Arc Testnet)
- Old single-owner PaymentSplitter (0xd54e8d2d…) superseded by SplitFactory

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, imported from `viem/chains`)
- Token: USDC (6 decimals) (Address: 0x3600000000000000000000000000000000000000, Chain: Arc Testnet)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Main application logic
- `src/components/` - UI components
- `src/config.ts` - wagmi config (chains, connectors, transports)

## To Run

```bash
bun install
bun run dev
```
