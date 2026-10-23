export function formatAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

export function formatUsdc(raw: bigint, decimals = 6): string {
  const n = Number(raw) / Math.pow(10, decimals)
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n)
}

export function parseUsdc(value: string, decimals = 6): bigint {
  const num = parseFloat(value)
  if (isNaN(num) || num <= 0) return 0n
  return BigInt(Math.round(num * Math.pow(10, decimals)))
}

export function bpsToPercent(bps: number | bigint): string {
  const n = typeof bps === 'bigint' ? Number(bps) : bps
  const val = n / 100
  if (Number.isInteger(val)) return String(val)
  return val.toFixed(2).replace(/\.?0+$/, '')
}

export function parseOnchainError(error: unknown): string {
  const msg = (error as Error)?.message?.toLowerCase() ?? ''
  if (msg.includes('user rejected') || msg.includes('user denied')) return 'Transaction cancelled.'
  if (msg.includes('insufficient')) return 'Insufficient balance.'
  if (msg.includes('unauthorized')) return 'Only the split creator can do this.'
  if (msg.includes('invalidsplit')) return 'Invalid split configuration.'
  if (msg.includes('nobalance')) return 'This split has no USDC balance.'
  if (msg.includes('splitnotfound')) return 'Split not found.'
  if (msg.includes('zeroamount')) return 'Amount must be greater than zero.'
  if (msg.includes('zeroaddress')) return 'Recipient address cannot be zero.'
  if (msg.includes('nopendin')) return 'No pending dust to rescue.'
  if (msg.includes('reverted')) return 'Transaction reverted. Check your inputs.'
  if (msg.includes('network') || msg.includes('timeout')) return 'Network error. Please retry.'
  return 'Something went wrong. Please try again.'
}
