import { useEffect, useRef, useState } from 'react'
import {
  useAccount, useReadContract, useSwitchChain, useWaitForTransactionReceipt, useWriteContract,
} from 'wagmi'
import { erc20Abi, formatUnits, type Abi } from 'viem'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { NetworkArc, NetworkBase } from '@web3icons/react'
import { ArrowLeftRight, Check, ExternalLink, Loader2, AlertTriangle, Clock } from 'lucide-react'
import { toast } from 'sonner'
import { CHAINS, type ChainKey } from '@/contract'
import { useChain, useChainSwitch } from '@/hooks/useChain'
import { useFeeConfig } from '@/hooks/useFeeConfig'
import { useActivity, announceAward, useNow } from '@/hooks/usePoints'
import { estimateAward } from '@/hooks/strTiers'
import { StrNotice } from '@/components/StrNotice'
import {
  BRIDGE_POLL_MS, BRIDGE_SLOW_MS, FAST_FINALITY, computeBridge, fetchBridgeStatus, fetchFeeQuote, usePendingBridge,
  type BridgeStage,
} from '@/bridge'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { parseUsdc, parseOnchainError, bpsToPercent } from '@/utils'
import { DATA_SUFFIX } from '@/attribution'

const card: React.CSSProperties = {
  background: 'rgba(255,255,255,0.035)',
  border: '1px solid rgba(245,200,66,0.12)',
  boxShadow: '0 4px 24px rgba(0,0,0,0.24)',
}

/** USDC amount with up to 4 decimals, trailing zeros trimmed (keeps at least 2). */
function fmt(raw: bigint): string {
  const [whole, frac = ''] = formatUnits(raw, 6).split('.')
  const trimmed = frac.replace(/0+$/, '').padEnd(2, '0')
  return `${Number(whole).toLocaleString('en-US')}.${trimmed}`
}

function Logo({ k, size = 28 }: { k: ChainKey; size?: number }) {
  const L = k === 'arc' ? NetworkArc : NetworkBase
  return (
    <span aria-hidden className="flex shrink-0 items-center justify-center overflow-hidden rounded-lg" style={{ width: size, height: size, boxShadow: '0 0 0 1px rgba(255,255,255,0.14)' }}>
      <L variant="background" size={size} />
    </span>
  )
}

function Row({ label, value, strong, muted }: { label: string; value: React.ReactNode; strong?: boolean; muted?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2">
      <span className="text-sm" style={{ color: muted ? 'var(--subtle)' : 'var(--muted)' }}>{label}</span>
      <span className={`text-sm tabular-nums text-right ${strong ? 'font-bold' : 'font-medium'}`} style={{ color: strong ? 'var(--accent)' : 'var(--ink-2)' }}>
        {value}
      </span>
    </div>
  )
}

// ─── In-progress transfer tracker ────────────────────────────────────────────

function Tracker() {
  const { address } = useAccount()
  const { pending, clearPending } = usePendingBridge(address)
  const now = useNow()

  const { data } = useQuery({
    queryKey: ['bridge-status', pending?.txHash],
    queryFn: () => fetchBridgeStatus(pending!.srcDomain, pending!.txHash),
    enabled: !!pending,
    refetchInterval: q => {
      const st = q.state.data?.stage
      return st === 'complete' || st === 'failed' ? false : BRIDGE_POLL_MS
    },
    retry: true,
    retryDelay: 1000,
  })

  // The fastest signal: the recipient's balance on the destination chain going up.
  const { data: dstBalance } = useReadContract({
    address: pending?.dstUsdc, abi: erc20Abi, functionName: 'balanceOf',
    args: [pending?.recipient ?? '0x0000000000000000000000000000000000000000'],
    chainId: pending?.dstChainId,
    query: { enabled: !!pending && pending.dstBalanceBefore != null && !!pending.dstUsdc, refetchInterval: BRIDGE_POLL_MS },
  })

  if (!pending) return null

  // (A transfer saved by an older version has no balance snapshot; the status service covers it.)
  const arrived = dstBalance !== undefined && pending.dstBalanceBefore != null && !!pending.minReceive
    && dstBalance >= BigInt(pending.dstBalanceBefore) + BigInt(pending.minReceive)
  const stage: BridgeStage = arrived ? 'complete' : data?.stage ?? 'attesting'
  const done = stage === 'complete'
  const failed = stage === 'failed'
  const elapsed = Math.max(0, now - pending.startedAt)
  const slow = !done && !failed && elapsed > BRIDGE_SLOW_MS
  const active = done ? 3 : stage === 'forwarding' ? 2 : 1 // index of the step in progress
  const src = Object.values(CHAINS).find(c => c.id === pending.srcChainId)
  const dst = Object.values(CHAINS).find(c => c.id === pending.dstChainId)
  const burnUrl = buildTxExplorerUrl(pending.srcChainId, pending.txHash)
  const mintUrl = data?.mintTx ? buildTxExplorerUrl(pending.dstChainId, data.mintTx) : null
  const secs = Math.floor(elapsed / 1000)
  const steps = [`Sent from ${src?.label}`, 'Confirmed', `Received on ${dst?.label}`]
  const progress = done ? 100 : stage === 'forwarding' ? 66 : 33

  return (
    <div className="rounded-3xl p-6" style={{
      background: done ? 'rgba(245,200,66,0.07)' : failed ? 'rgba(248,113,113,0.07)' : 'rgba(255,255,255,0.04)',
      border: `1px solid ${done ? 'rgba(245,200,66,0.28)' : failed ? 'rgba(248,113,113,0.30)' : 'rgba(245,200,66,0.16)'}`,
      boxShadow: '0 8px 40px rgba(0,0,0,0.3)',
    }}>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="display text-base font-bold" style={{ color: failed ? '#FCA5A5' : done ? 'var(--accent)' : 'var(--ink)' }}>
            {done ? 'Bridge complete' : failed ? 'Delivery needs attention' : 'Bridge in progress'}
          </p>
          <p className="mt-0.5 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
            {pending.amount} USDC · {src?.label} → {dst?.label}
          </p>
        </div>
        {!done && !failed && (
          <span className="flex items-center gap-1.5 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
            <Clock className="size-3.5" />{secs}s
          </span>
        )}
      </div>

      <div className="mb-5 h-1 overflow-hidden rounded-full" style={{ background: 'rgba(255,255,255,0.08)' }}>
        <div className="h-full rounded-full transition-all duration-700 ease-out" style={{
          width: `${failed ? 100 : progress}%`,
          background: failed ? '#F87171' : 'var(--accent)',
          boxShadow: done ? '0 0 12px rgba(245,200,66,0.5)' : 'none',
        }} />
      </div>

      <ol className="space-y-3">
        {steps.map((label, i) => {
          const complete = i < active
          const current = i === active && !failed
          return (
            <li key={label} className="flex items-center gap-3">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-bold" style={{
                background: complete ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
                color: complete ? '#0c0c0c' : 'var(--subtle)',
                boxShadow: current ? '0 0 0 1.5px rgba(245,200,66,0.55)' : 'none',
              }}>
                {complete ? <Check className="size-3.5" /> : current ? <Loader2 className="size-3.5 animate-spin" style={{ color: 'var(--accent)' }} /> : i + 1}
              </span>
              <span className="text-sm" style={{ color: complete || current ? 'var(--ink-2)' : 'var(--subtle)' }}>{label}</span>
            </li>
          )
        })}
      </ol>

      {done && (
        <p className="mt-4 text-sm" style={{ color: 'var(--ink-2)' }}>
          <b style={{ color: 'var(--accent)' }}>{pending.receive} USDC</b> arrived on {dst?.label}.
        </p>
      )}
      {failed && (
        <p className="mt-4 flex items-start gap-2 text-xs leading-relaxed" style={{ color: '#FCA5A5' }}>
          <AlertTriangle className="mt-0.5 size-3.5 shrink-0" />
          The automatic delivery did not finish. Your USDC is safe: it was sent from {src?.label} and can still be completed on {dst?.label} using the transfer&rsquo;s confirmation.
        </p>
      )}
      {slow && (
        <p className="mt-4 text-xs leading-relaxed" style={{ color: 'var(--muted)' }}>
          This is taking longer than usual. Transfers normally finish within a minute. You can keep waiting or dismiss this; the transfer continues either way.
        </p>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2">
        <a href={burnUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-xs" style={{ color: 'var(--muted)' }}>
          Sent transaction <ExternalLink className="size-3" />
        </a>
        {mintUrl && (
          <a href={mintUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-xs" style={{ color: 'var(--muted)' }}>
            Received transaction <ExternalLink className="size-3" />
          </a>
        )}
        {(done || failed || slow) && (
          <button onClick={clearPending} className="ml-auto text-xs font-semibold" style={{ color: 'var(--accent)' }}>
            {done ? 'Bridge more' : 'Dismiss'}
          </button>
        )}
      </div>
    </div>
  )
}

// ─── Bridge form ──────────────────────────────────────────────────────────────

export function BridgePage() {
  const chain = useChain()
  const { setChainKey } = useChainSwitch()
  const dest = CHAINS[chain.key === 'arc' ? 'base' : 'arc']
  const queryClient = useQueryClient()
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== chain.id
  const [amount, setAmount] = useState('')
  const { pending, setPending } = usePendingBridge(address)

  const srcDomain = chain.cctpDomain
  const dstDomain = dest.cctpDomain

  const { data: feeQuote, isLoading: quoteLoading, isError: quoteError } = useQuery({
    queryKey: ['cctp-fees', srcDomain, dstDomain],
    queryFn: () => fetchFeeQuote(srcDomain, dstDomain),
    refetchInterval: 30_000,
    staleTime: 20_000,
  })

  const { feeBps } = useFeeConfig()
  const { earnedToday, tierToday } = useActivity()

  const { data: balance, refetch: refetchBal } = useReadContract({
    address: chain.usdc, abi: erc20Abi, functionName: 'balanceOf',
    args: [address!], chainId: chain.id, query: { enabled: !!address },
  })
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: chain.usdc, abi: erc20Abi, functionName: 'allowance',
    args: [address!, chain.points.address], chainId: chain.id, query: { enabled: !!address },
  })

  // Destination balance, so the tracker can see the arrival the moment it happens.
  const { data: destBalance } = useReadContract({
    address: dest.usdc, abi: erc20Abi, functionName: 'balanceOf',
    args: [address!], chainId: dest.id, query: { enabled: !!address, refetchInterval: 5000 },
  })

  const parsed = parseUsdc(amount)
  const bps = feeBps !== undefined ? BigInt(feeBps) : undefined
  const quote = feeQuote && bps !== undefined && parsed > 0n ? computeBridge(parsed, bps, feeQuote) : null
  const estimate = estimateAward(parsed, earnedToday, tierToday)
  const insufficient = balance !== undefined && parsed > balance
  const needsApproval = parsed > 0n && (allowance === undefined || allowance < parsed)
  const locked = !!pending

  const { writeContract: approve, data: approveHash, isPending: approveP } = useWriteContract()
  const { isLoading: approveConf } = useWaitForTransactionReceipt({ hash: approveHash, query: { enabled: !!approveHash } })
  const { writeContract: bridge, data: bridgeHash, isPending: bridgeP, reset: resetBridge } = useWriteContract()
  const { isLoading: bridgeConf, isSuccess: bridgeDone, isError: bridgeFailed, data: receipt } = useWaitForTransactionReceipt({
    hash: bridgeHash, pollingInterval: 1000, query: { enabled: !!bridgeHash },
  })
  const busy = approveP || approveConf || bridgeP || bridgeConf

  // Details captured at click time, so the tracker is right even if the form changes while confirming.
  const sent = useRef<{
    amount: string; receive: string; srcChainId: number; dstChainId: number; srcDomain: number
    recipient: `0x${string}`; dstUsdc: `0x${string}`; dstBalanceBefore: string | null; minReceive: string
  } | null>(null)

  // Burn confirmed: start tracking, refresh balances and STR.
  const notified = useRef<string | null>(null)
  useEffect(() => {
    if (!bridgeDone || !bridgeHash || !sent.current || notified.current === bridgeHash) return
    notified.current = bridgeHash
    setPending({ txHash: bridgeHash, ...sent.current, startedAt: Date.now() })
    announceAward(receipt?.logs ?? [], chain.points.abi as Abi)
    void refetchBal()
    void refetchAllowance()
    void queryClient.invalidateQueries()
    resetBridge()
  }, [bridgeDone, bridgeHash, receipt, setPending, chain.points.abi, refetchBal, refetchAllowance, queryClient, resetBridge])

  const handleApprove = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    approve({
      address: chain.usdc, abi: erc20Abi, functionName: 'approve',
      args: [chain.points.address, parsed], chainId: chain.id, dataSuffix: DATA_SUFFIX,
    }, {
      onSuccess: () => { void refetchAllowance(); toast.success('Approval confirmed.') },
      onError: e => toast.error(parseOnchainError(e)),
    })
  }

  const handleBridge = () => {
    if (isWrongChain) { switchChain({ chainId: chain.id }); return }
    if (!quote || !quote.valid || !address || feeBps === undefined) return
    sent.current = {
      amount: fmt(quote.amount), receive: fmt(quote.receiveEst),
      srcChainId: chain.id, dstChainId: dest.id, srcDomain,
      recipient: address, dstUsdc: dest.usdc,
      dstBalanceBefore: destBalance !== undefined ? destBalance.toString() : null,
      minReceive: quote.receiveMin.toString(),
    }
    bridge({
      address: chain.points.address, abi: chain.points.abi, functionName: 'bridge',
      args: [parsed, quote.maxFee, FAST_FINALITY, address, feeBps], chainId: chain.id, dataSuffix: DATA_SUFFIX,
    }, {
      onError: e => toast.error(parseOnchainError(e)),
    })
  }

  // What the primary button says / does
  let label = `Bridge to ${dest.label}`
  let action: (() => void) | null = handleBridge
  let disabled = false
  if (!isConnected) { label = 'Connect wallet to bridge'; action = null; disabled = true }
  else if (locked) { label = 'Bridge in progress'; action = null; disabled = true }
  else if (isWrongChain) { label = `Switch to ${chain.label}`; action = () => switchChain({ chainId: chain.id }) }
  else if (parsed === 0n) { label = 'Enter an amount'; action = null; disabled = true }
  else if (insufficient) { label = 'Insufficient USDC'; action = null; disabled = true }
  else if (quoteLoading || bps === undefined) { label = 'Loading fees…'; action = null; disabled = true }
  else if (quoteError || !feeQuote) { label = 'Fees unavailable'; action = null; disabled = true }
  else if (quote && !quote.valid) { label = 'Amount too small for fees'; action = null; disabled = true }
  else if (needsApproval) { label = 'Approve USDC'; action = handleApprove }
  if (busy) { disabled = true }

  return (
    <div className="space-y-4">
      <Tracker />

      {/* Route + amount */}
      <div className="rounded-3xl p-6" style={card}>
        <div className="flex items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-2.5">
            <Logo k={chain.key} />
            <div className="min-w-0">
              <p className="text-[0.65rem] font-semibold uppercase tracking-widest" style={{ color: 'var(--subtle)' }}>From</p>
              <p className="display text-base font-bold" style={{ color: 'var(--ink)' }}>{chain.label}</p>
            </div>
          </div>
          <button
            onClick={() => setChainKey(dest.key)}
            disabled={busy || locked}
            aria-label={`Switch direction: bridge from ${dest.label} to ${chain.label}`}
            className="flex size-10 shrink-0 items-center justify-center rounded-full transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-40"
            style={{ background: 'rgba(245,200,66,0.10)', border: '1px solid rgba(245,200,66,0.25)', color: 'var(--accent)' }}
          >
            <ArrowLeftRight className="size-4" />
          </button>
          <div className="flex min-w-0 items-center justify-end gap-2.5 text-right">
            <div className="min-w-0">
              <p className="text-[0.65rem] font-semibold uppercase tracking-widest" style={{ color: 'var(--subtle)' }}>To</p>
              <p className="display text-base font-bold" style={{ color: 'var(--ink)' }}>{dest.label}</p>
            </div>
            <Logo k={dest.key} />
          </div>
        </div>

        <div className="my-5 h-px" style={{ background: 'rgba(255,255,255,0.07)' }} />

        <div className="mb-3 flex items-center justify-between">
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>Amount</span>
          {balance !== undefined && (
            <button
              onClick={() => setAmount(formatUnits(balance, 6))}
              disabled={locked || busy}
              className="text-xs tabular-nums disabled:opacity-50"
              style={{ color: 'var(--muted)' }}
            >
              Balance {fmt(balance)} · <span style={{ color: 'var(--accent)' }}>Max</span>
            </button>
          )}
        </div>
        <div className="flex items-center gap-3 rounded-2xl px-4 py-3.5" style={{ background: 'rgba(0,0,0,0.28)', boxShadow: 'inset 0 0 0 1px rgba(245,200,66,0.14)' }}>
          <input
            inputMode="decimal"
            placeholder="0.00"
            value={amount}
            onChange={e => setAmount(e.target.value.replace(/[^0-9.]/g, ''))}
            disabled={locked || busy}
            className="min-w-0 flex-1 bg-transparent text-3xl font-bold tabular-nums outline-none disabled:opacity-60"
            style={{ color: 'var(--ink)' }}
          />
          <span className="text-sm font-semibold" style={{ color: 'var(--muted)' }}>USDC</span>
        </div>

        {quote && parsed > 0n && (
          <div className="mt-4 divide-y" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
            <Row label="You send" value={`${fmt(quote.amount)} USDC`} />
            <Row label={`Platform fee (${bpsToPercent(bps!)}%)`} value={`− ${fmt(quote.platformFee)}`} muted />
            <Row label="Network fee" value={`− ${fmt(quote.networkFeeEst)}`} muted />
            <Row label={`You receive on ${dest.label}`} value={quote.valid ? `${fmt(quote.receiveEst)} USDC` : '—'} strong />
          </div>
        )}
        {quote && !quote.valid && parsed > 0n && (
          <p className="mt-3 text-xs" style={{ color: '#FDBA74' }}>
            This amount is too small to cover the network fee. Try a larger amount.
          </p>
        )}

        {parsed > 0n && <div className="mt-4"><StrNotice est={estimate} what="bridge" /></div>}
      </div>

      {/* Action */}
      <button
        onClick={() => action?.()}
        disabled={disabled}
        className="flex w-full items-center justify-center gap-2 rounded-2xl py-4 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed"
        style={{
          background: disabled ? 'rgba(255,255,255,0.06)' : 'var(--accent)',
          color: disabled ? 'var(--muted)' : '#0c0c0c',
          boxShadow: disabled ? 'none' : '0 4px 32px rgba(245,200,66,0.28), 0 0 0 1px rgba(245,200,66,0.20)',
          opacity: disabled && !busy ? 0.7 : 1,
        }}
      >
        {busy
          ? <><Loader2 className="size-4 animate-spin" />{approveP || bridgeP ? 'Confirm in wallet…' : approveConf ? 'Approving…' : 'Bridging…'}</>
          : label}
      </button>

      {bridgeFailed && (
        <p className="flex items-center gap-2 text-xs" style={{ color: '#FCA5A5' }}>
          <AlertTriangle className="size-3.5" /> The bridge transaction failed. Nothing was sent; you can try again.
        </p>
      )}

      <p className="px-2 text-center text-xs leading-relaxed" style={{ color: 'var(--subtle)' }}>
        Powered by CCTP Fast Transfer. Usually arrives in under a minute. Only one bridge can run at a time.
      </p>
    </div>
  )
}
