/**
 * Local-only (localStorage) display data for splits: titles, recipient labels and
 * hidden splits. Nothing here is sent onchain.
 *
 * Each chain has its own independent splits, so every key is scoped by chain ID.
 * Arc keeps the original un-prefixed keys so data saved before multi-chain
 * support still shows up; other chains use a "c{chainId}-" prefix.
 */
import { CHAINS } from '@/contract'

const prefix = (chainId: number) => (chainId === CHAINS.arc.id ? '' : `c${chainId}-`)

const TITLE_KEY = (chainId: number, id: bigint) => `${prefix(chainId)}split-title-${id.toString()}`

export function getSplitTitle(chainId: number, id: bigint): string {
  try { return localStorage.getItem(TITLE_KEY(chainId, id)) ?? '' } catch { return '' }
}

export function setSplitTitle(chainId: number, id: bigint, title: string): void {
  try {
    const trimmed = title.trim()
    if (trimmed) localStorage.setItem(TITLE_KEY(chainId, id), trimmed)
    else localStorage.removeItem(TITLE_KEY(chainId, id))
  } catch { /* storage unavailable — silent */ }
}

/** Display label: title if set, else "Split #N" */
export function splitLabel(chainId: number, id: bigint): string {
  const t = getSplitTitle(chainId, id)
  return t || `Split #${id.toString()}`
}

// ─── Hidden splits (local-only "delete") ──────────────────────────────────────
// The contract is immutable; hiding only removes the split from the local list.
// The split still exists onchain and is accessible via Jump to split.

const HIDDEN_KEY = (chainId: number) => `${prefix(chainId)}split-hidden-ids`

function readHidden(chainId: number): Set<string> {
  try {
    const raw = localStorage.getItem(HIDDEN_KEY(chainId))
    if (!raw) return new Set()
    return new Set(JSON.parse(raw) as string[])
  } catch { return new Set() }
}

function writeHidden(chainId: number, set: Set<string>): void {
  try { localStorage.setItem(HIDDEN_KEY(chainId), JSON.stringify([...set])) } catch { /* silent */ }
}

export function hideSplit(chainId: number, id: bigint): void {
  const s = readHidden(chainId)
  s.add(id.toString())
  writeHidden(chainId, s)
}

export function isHidden(chainId: number, id: bigint): boolean {
  return readHidden(chainId).has(id.toString())
}

/** Filter an array of IDs, removing any that have been locally hidden. */
export function filterVisible(chainId: number, ids: bigint[]): bigint[] {
  const hidden = readHidden(chainId)
  return ids.filter(id => !hidden.has(id.toString()))
}

// ─── Recipient labels (optional display name / social handle) ─────────────────
// Key format: "{prefix}split-{id}-label-{addr_lowercase}"

const LABEL_KEY = (chainId: number, id: bigint, addr: string) =>
  `${prefix(chainId)}split-${id.toString()}-label-${addr.toLowerCase()}`

export function getRecipientLabel(chainId: number, id: bigint, addr: string): string {
  try { return localStorage.getItem(LABEL_KEY(chainId, id, addr)) ?? '' } catch { return '' }
}

export function setRecipientLabel(chainId: number, id: bigint, addr: string, label: string): void {
  try {
    const trimmed = label.trim()
    if (trimmed) localStorage.setItem(LABEL_KEY(chainId, id, addr), trimmed)
    else localStorage.removeItem(LABEL_KEY(chainId, id, addr))
  } catch { /* storage unavailable — silent */ }
}
