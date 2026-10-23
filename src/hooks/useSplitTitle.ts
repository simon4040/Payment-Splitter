/**
 * Stores and retrieves an optional display title for each split.
 * Titles are local-only (localStorage) — they are never sent to the chain.
 * Key format: "split-title-{id}"
 */

const KEY = (id: bigint) => `split-title-${id.toString()}`

export function getSplitTitle(id: bigint): string {
  try { return localStorage.getItem(KEY(id)) ?? '' } catch { return '' }
}

export function setSplitTitle(id: bigint, title: string): void {
  try {
    const trimmed = title.trim()
    if (trimmed) localStorage.setItem(KEY(id), trimmed)
    else localStorage.removeItem(KEY(id))
  } catch { /* storage unavailable — silent */ }
}

/** Display label: title if set, else "Split #N" */
export function splitLabel(id: bigint): string {
  const t = getSplitTitle(id)
  return t || `Split #${id.toString()}`
}

// ─── Hidden splits (local-only "delete") ──────────────────────────────────────
// The contract is immutable; hiding only removes the split from the local list.
// The split still exists onchain and is accessible via Jump to split.

const HIDDEN_KEY = 'split-hidden-ids'

function readHidden(): Set<string> {
  try {
    const raw = localStorage.getItem(HIDDEN_KEY)
    if (!raw) return new Set()
    return new Set(JSON.parse(raw) as string[])
  } catch { return new Set() }
}

function writeHidden(set: Set<string>): void {
  try { localStorage.setItem(HIDDEN_KEY, JSON.stringify([...set])) } catch { /* silent */ }
}

export function hideSplit(id: bigint): void {
  const s = readHidden()
  s.add(id.toString())
  writeHidden(s)
}

export function isHidden(id: bigint): boolean {
  return readHidden().has(id.toString())
}

/** Filter an array of IDs, removing any that have been locally hidden. */
export function filterVisible(ids: bigint[]): bigint[] {
  const hidden = readHidden()
  return ids.filter(id => !hidden.has(id.toString()))
}

// ─── Recipient labels (optional display name / social handle) ─────────────────
// Stored locally in localStorage; never sent onchain.
// Key format: "split-{id}-label-{addr_lowercase}"

const LABEL_KEY = (id: bigint, addr: string) =>
  `split-${id.toString()}-label-${addr.toLowerCase()}`

export function getRecipientLabel(id: bigint, addr: string): string {
  try { return localStorage.getItem(LABEL_KEY(id, addr)) ?? '' } catch { return '' }
}

export function setRecipientLabel(id: bigint, addr: string, label: string): void {
  try {
    const trimmed = label.trim()
    if (trimmed) localStorage.setItem(LABEL_KEY(id, addr), trimmed)
    else localStorage.removeItem(LABEL_KEY(id, addr))
  } catch { /* storage unavailable — silent */ }
}
