/**
 * Displays full details for one split: balance hero, recipients list,
 * distribute button, and deposit panel.
 */
import { useState, useEffect, useRef } from 'react'
import {
  useAccount, useReadContract, useWriteContract,
  useWaitForTransactionReceipt, useSwitchChain,
} from 'wagmi'
import { erc20Abi } from 'viem'
import { Loader2, ExternalLink, ArrowDownToLine, Send, GitBranch, Copy, Check } from 'lucide-react'
import { toast } from 'sonner'
import { TokenUSDC } from '@web3icons/react'
import { SPLIT_FACTORY, ARC_MAINNET_USDC, ARC_MAINNET_ID } from '@/contract'
import { formatUsdc, parseUsdc, bpsToPercent, formatAddress, parseOnchainError } from '@/utils'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { Amount, usdcDecimalsFor } from '@/onchain-money'
import { getRecipientLabel } from '@/hooks/useSplitTitle'

// ─── Copy button ──────────────────────────────────────────────────────────────

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)
  const handle = () => {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1800)
    })
  }
  return (
    <button
      onClick={handle}
      title={copied ? 'Copied!' : 'Copy address'}
      className="shrink-0 flex items-center gap-1 rounded-lg px-1.5 py-0.5 text-xs transition-all"
      style={{
        color: copied ? 'var(--success)' : 'var(--subtle)',
        background: copied ? 'rgba(245,200,66,0.08)' : 'transparent',
      }}
      onMouseEnter={e => { if (!copied) e.currentTarget.style.color = 'var(--muted)' }}
      onMouseLeave={e => { if (!copied) e.currentTarget.style.color = 'var(--subtle)' }}
    >
      {copied
        ? <><Check className="size-3" /><span>Copied</span></>
        : <Copy className="size-3" />}
    </button>
  )
}

interface Props { splitId: bigint }

const QUICK_AMOUNTS = ['1', '5', '10', '25', '100']

// ─── Deposit ──────────────────────────────────────────────────────────────────

function DepositSection({ splitId, onDeposited }: { splitId: bigint; onDeposited: () => void }) {
  const [amount, setAmount] = useState('')
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== ARC_MAINNET_ID

  const { data: userBalance, refetch: refetchBal } = useReadContract({
    address: ARC_MAINNET_USDC, abi: erc20Abi, functionName: 'balanceOf',
    args: [address!], chainId: ARC_MAINNET_ID,
    query: { enabled: !!address },
  })
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: ARC_MAINNET_USDC, abi: erc20Abi, functionName: 'allowance',
    args: [address!, SPLIT_FACTORY.address], chainId: ARC_MAINNET_ID,
    query: { enabled: !!address },
  })

  const formattedBal = userBalance !== undefined
    ? Amount.fromRaw(userBalance, usdcDecimalsFor(ARC_MAINNET_ID)).toFixed(2)
    : null

  const parsed = parseUsdc(amount)
  const needsApproval = parsed > 0n && (allowance === undefined || allowance < parsed)

  const { writeContract: approve, data: approveHash, isPending: approveP } = useWriteContract()
  const { isLoading: approveConf } = useWaitForTransactionReceipt({
    hash: approveHash, query: { enabled: !!approveHash },
  })

  const { writeContract: deposit, data: depositHash, isPending: depositP, reset: resetDeposit } = useWriteContract()
  const { isLoading: depositConf, isSuccess: depositDone } = useWaitForTransactionReceipt({
    hash: depositHash, query: { enabled: !!depositHash },
  })

  const txUrl = depositHash ? buildTxExplorerUrl(ARC_MAINNET_ID, depositHash) : null
  const isBusy = approveP || approveConf || depositP || depositConf

  const notifiedDepositRef = useRef<string | null>(null)
  useEffect(() => {
    if (!depositDone || !depositHash || notifiedDepositRef.current === depositHash) return
    notifiedDepositRef.current = depositHash
    void refetchBal()
    void refetchAllowance()
    onDeposited()
  }, [depositDone, depositHash, refetchBal, refetchAllowance, onDeposited])

  const handleApprove = () => {
    if (isWrongChain) { switchChain({ chainId: ARC_MAINNET_ID }); return }
    approve({
      address: ARC_MAINNET_USDC, abi: erc20Abi, functionName: 'approve',
      args: [SPLIT_FACTORY.address, parsed], chainId: ARC_MAINNET_ID,
    }, {
      onSuccess: () => { void refetchAllowance(); toast.success('Approval confirmed.') },
      onError: (err) => toast.error(parseOnchainError(err)),
    })
  }

  const handleDeposit = () => {
    if (isWrongChain) { switchChain({ chainId: ARC_MAINNET_ID }); return }
    deposit({
      address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi, functionName: 'deposit',
      args: [splitId, parsed], chainId: ARC_MAINNET_ID,
    }, {
      onError: (err) => toast.error(parseOnchainError(err)),
    })
  }

  if (depositDone) {
    return (
      <div className="rounded-2xl p-4 flex items-center justify-between" style={{
        background: 'rgba(245,200,66,0.06)', border: '1px solid rgba(245,200,66,0.20)',
      }}>
        <div className="flex items-center gap-3">
          <div className="size-8 rounded-full flex items-center justify-center" style={{ background: 'rgba(245,200,66,0.12)' }}>
            <svg className="size-4" viewBox="0 0 20 20" fill="none">
              <path d="M4 10l4 4 8-8" stroke="#F5C842" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
          <div>
            <p className="text-sm font-semibold" style={{ color: 'var(--success)' }}>USDC deposited</p>
            {txUrl && (
              <a href={txUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-xs mt-0.5" style={{ color: 'var(--muted)' }}>
                View on explorer <ExternalLink className="size-3" />
              </a>
            )}
          </div>
        </div>
        <button onClick={() => { resetDeposit(); setAmount('') }} className="text-xs font-medium" style={{ color: 'var(--muted)' }}>
          Deposit more
        </button>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <div className="rounded-2xl px-4 py-3.5" style={{ background: 'rgba(255,255,255,0.04)', boxShadow: '0 0 0 1px rgba(245,200,66,0.10)' }}>
        <input
          inputMode="decimal" value={amount}
          onChange={e => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d*$/.test(v)) setAmount(v) }}
          placeholder="0.00"
          className="display w-full bg-transparent text-3xl font-bold tabular-nums outline-none placeholder:opacity-20"
          style={{ color: 'var(--ink)' }}
        />
        <div className="mt-1 flex items-center justify-between">
          <span className="text-xs font-medium" style={{ color: 'var(--muted)' }}>USDC</span>
          {formattedBal !== null && (
            <button onClick={() => setAmount(formattedBal)} className="text-xs font-semibold" style={{ color: 'var(--accent)' }}>
              {formattedBal} max
            </button>
          )}
        </div>
      </div>

      <div className="flex gap-1.5 flex-wrap">
        {QUICK_AMOUNTS.map(q => (
          <button key={q} onClick={() => setAmount(q)}
            className="rounded-full px-3 py-1 text-xs font-semibold transition-all"
            style={{
              background: amount === q ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
              color: amount === q ? '#0c0c0c' : 'var(--muted)',
              boxShadow: amount === q ? '0 0 14px rgba(245,200,66,0.25)' : '0 0 0 1px rgba(255,255,255,0.09)',
            }}>
            ${q}
          </button>
        ))}
      </div>

      {!isConnected ? (
        <p className="text-xs text-center" style={{ color: 'var(--muted)' }}>Connect your wallet to deposit</p>
      ) : needsApproval ? (
        <button disabled={parsed === 0n || isBusy} onClick={isWrongChain ? () => switchChain({ chainId: ARC_MAINNET_ID }) : handleApprove}
          className="w-full rounded-2xl py-3.5 text-sm font-semibold transition-all active:scale-[0.99] disabled:opacity-40 disabled:cursor-not-allowed"
          style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)', boxShadow: '0 0 0 1px rgba(245,200,66,0.22)' }}>
          {isBusy
            ? <span className="flex items-center justify-center gap-2"><Loader2 className="size-4 animate-spin" />Approving…</span>
            : isWrongChain ? 'Switch Network' : 'Approve USDC'}
        </button>
      ) : (
        <button disabled={parsed === 0n || isBusy} onClick={isWrongChain ? () => switchChain({ chainId: ARC_MAINNET_ID }) : handleDeposit}
          className="w-full rounded-2xl py-3.5 text-sm font-semibold transition-all active:scale-[0.99] disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          style={{
            background: parsed > 0n ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
            color: parsed > 0n ? '#0c0c0c' : 'var(--muted)',
            boxShadow: parsed > 0n && !isBusy ? '0 0 28px rgba(245,200,66,0.24)' : 'none',
          }}>
          {isBusy ? <><Loader2 className="size-4 animate-spin" />Depositing…</>
            : isWrongChain ? 'Switch Network'
            : <><Send className="size-4" />{amount ? `Deposit ${amount} USDC` : 'Deposit USDC'}</>}
        </button>
      )}
    </div>
  )
}

// ─── Distribute ───────────────────────────────────────────────────────────────

function DistributeSection({
  splitId, balance, onDistributed,
}: {
  splitId: bigint
  balance: bigint
  onDistributed: () => void
}) {
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const isWrongChain = isConnected && chainId !== ARC_MAINNET_ID
  const canDistribute = balance > 0n

  const { writeContract, data: hash, isPending, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash, query: { enabled: !!hash },
  })

  const txUrl = hash ? buildTxExplorerUrl(ARC_MAINNET_ID, hash) : null
  const notifiedRef = useRef<string | null>(null)

  useEffect(() => {
    if (!isSuccess || !hash || notifiedRef.current === hash) return
    notifiedRef.current = hash
    onDistributed()
  }, [isSuccess, hash, onDistributed])

  const handleDistribute = () => {
    if (isWrongChain) { switchChain({ chainId: ARC_MAINNET_ID }); return }
    writeContract({
      address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi,
      functionName: 'distribute', args: [splitId], chainId: ARC_MAINNET_ID,
    }, {
      onSuccess: () => toast.success('Distributed to all recipients.'),
      onError: (err) => toast.error(parseOnchainError(err)),
    })
  }

  if (isSuccess) {
    return (
      <div className="rounded-2xl p-4 flex items-center justify-between" style={{
        background: 'rgba(245,200,66,0.06)', border: '1px solid rgba(245,200,66,0.20)',
      }}>
        <div className="flex items-center gap-3">
          <div className="size-8 rounded-full flex items-center justify-center" style={{ background: 'rgba(245,200,66,0.12)' }}>
            <svg className="size-4" viewBox="0 0 20 20" fill="none">
              <path d="M4 10l4 4 8-8" stroke="#F5C842" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
          <div>
            <p className="text-sm font-semibold" style={{ color: 'var(--success)' }}>Distributed</p>
            {txUrl && (
              <a href={txUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-xs mt-0.5" style={{ color: 'var(--muted)' }}>
                View on explorer <ExternalLink className="size-3" />
              </a>
            )}
          </div>
        </div>
        <button onClick={reset} className="text-xs font-medium" style={{ color: 'var(--muted)' }}>Reset</button>
      </div>
    )
  }

  if (!isConnected) {
    return (
      <div className="rounded-2xl py-3.5 px-4 text-center text-sm" style={{
        background: 'rgba(255,255,255,0.04)', boxShadow: '0 0 0 1px rgba(245,200,66,0.10)',
        color: 'var(--muted)',
      }}>
        Connect wallet to distribute
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <button
        disabled={(!canDistribute && !isWrongChain) || isPending || isConfirming}
        onClick={handleDistribute}
        className="w-full rounded-2xl py-4 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed flex items-center justify-center gap-2"
        style={{
          background: canDistribute || isWrongChain ? 'var(--accent)' : 'rgba(255,255,255,0.06)',
          color: canDistribute || isWrongChain ? '#0c0c0c' : 'var(--muted)',
          boxShadow: canDistribute && !isPending && !isConfirming
            ? '0 4px 32px rgba(245,200,66,0.28), 0 0 0 1px rgba(245,200,66,0.20)'
            : 'none',
          opacity: (!canDistribute && !isWrongChain) ? 0.45 : 1,
        }}
      >
        {isWrongChain ? 'Switch Network'
          : isPending ? <><Loader2 className="size-4 animate-spin" /> Confirm in wallet…</>
          : isConfirming ? <><Loader2 className="size-4 animate-spin" /> Distributing…</>
          : <><ArrowDownToLine className="size-4" /> Distribute</>}
      </button>
      <p className="text-center text-xs" style={{ color: 'var(--muted)', opacity: 0.8 }}>
        {!canDistribute && !isWrongChain
          ? 'Deposit USDC to this split first'
          : 'Sends full balance to all recipients'}
      </p>
    </div>
  )
}

// ─── Root card ────────────────────────────────────────────────────────────────

export function SplitCard({ splitId }: Props) {
  const [optimisticBalanceZero, setOptimisticBalanceZero] = useState(false)

  const { data: splitData, isLoading: splitLoading, refetch: refetchSplit } = useReadContract({
    address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi,
    functionName: 'getSplit', args: [splitId], chainId: ARC_MAINNET_ID,
    query: { refetchInterval: 8000 },
  })
  const { data: recipientData, isLoading: recLoading } = useReadContract({
    address: SPLIT_FACTORY.address, abi: SPLIT_FACTORY.abi,
    functionName: 'getRecipients', args: [splitId], chainId: ARC_MAINNET_ID,
    query: { refetchInterval: 12000 },
  })

  const [creator, rawBalance, totalDistributed] = (splitData as [string, bigint, bigint, bigint] | undefined) ?? ['', 0n, 0n, 0n]
  const addrs = (recipientData as [string[], bigint[]] | undefined)?.[0] ?? []
  const bpsArr = (recipientData as [string[], bigint[]] | undefined)?.[1] ?? []

  const balance = optimisticBalanceZero && rawBalance > 0n ? 0n : rawBalance
  const isLoading = splitLoading || recLoading
  const formattedBalance = formatUsdc(balance)
  const hasBalance = balance > 0n

  const handleDistributed = () => {
    setOptimisticBalanceZero(true)
    void refetchSplit()
  }

  const handleDeposited = () => {
    setOptimisticBalanceZero(false)
    void refetchSplit()
  }

  return (
    <div className="space-y-4">
      {/* Balance hero */}
      <div className="rounded-3xl p-7" style={{
        background: 'linear-gradient(135deg, rgba(245,200,66,0.08) 0%, rgba(255,255,255,0.03) 100%)',
        border: '1px solid rgba(245,200,66,0.18)',
        boxShadow: '0 8px 40px rgba(0,0,0,0.36), inset 0 1px 0 rgba(255,255,255,0.05)',
      }}>
        <div className="flex items-center gap-2 mb-5">
          <TokenUSDC variant="branded" size={18} />
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.09em' }}>Balance</span>
          {hasBalance && (
            <span className="ml-auto flex items-center gap-1.5 text-xs font-medium rounded-full px-2.5 py-0.5"
              style={{ background: 'rgba(245,200,66,0.12)', color: 'var(--success)' }}>
              <span className="size-1.5 rounded-full bg-current animate-pulse inline-block" />
              Ready
            </span>
          )}
        </div>

        {isLoading ? (
          <div className="h-14 w-44 rounded-2xl animate-pulse" style={{ background: 'rgba(255,255,255,0.07)' }} />
        ) : (
          <>
            <div className="flex items-baseline gap-2.5">
              <span className="display font-bold tabular-nums" style={{ color: 'var(--ink)', fontSize: 'clamp(2.8rem,10vw,3.6rem)', letterSpacing: '-0.04em' }}>
                {formattedBalance}
              </span>
              <span className="text-xl font-medium" style={{ color: 'var(--muted)' }}>USDC</span>
            </div>
            {totalDistributed > 0n && (
              <p className="mt-2 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
                {formatUsdc(totalDistributed)} USDC distributed all-time
              </p>
            )}
          </>
        )}
      </div>

      {/* Recipients */}
      <div className="rounded-3xl p-6" style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(245,200,66,0.10)',
        boxShadow: '0 4px 20px rgba(0,0,0,0.20)',
      }}>
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2">
            <GitBranch className="size-3.5" style={{ color: 'var(--accent)' }} />
            <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--muted)', letterSpacing: '0.08em' }}>Recipients</span>
          </div>
          {addrs.length > 0 && (
            <span className="text-xs font-medium rounded-full px-2 py-0.5" style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--accent)' }}>
              {addrs.length}
            </span>
          )}
        </div>

        {recLoading ? (
          <div className="space-y-2.5">
            {[1, 2, 3].map(i => <div key={i} className="h-11 rounded-xl animate-pulse" style={{ background: 'rgba(255,255,255,0.06)' }} />)}
          </div>
        ) : addrs.length === 0 ? (
          <div className="py-10 flex flex-col items-center gap-3 text-center">
            <div className="size-12 rounded-2xl flex items-center justify-center" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(245,200,66,0.10)' }}>
              <GitBranch className="size-5" style={{ color: 'var(--subtle)' }} />
            </div>
            <div>
              <p className="text-sm font-medium" style={{ color: 'var(--muted)' }}>No recipients configured</p>
              <p className="text-xs mt-1" style={{ color: 'var(--subtle)' }}>This split has no recipients yet</p>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            {addrs.map((addr, i) => {
              const pct = bpsToPercent(bpsArr[i] ?? 0n)
              const width = `${(Number(bpsArr[i] ?? 0n) / 100)}%`
              const label = getRecipientLabel(splitId, addr)
              return (
                <div key={addr} className="rounded-2xl px-4 py-3" style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(245,200,66,0.08)' }}>
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className="size-5 rounded-full flex items-center justify-center shrink-0"
                        style={{ background: 'rgba(245,200,66,0.10)', color: 'var(--muted)', fontSize: '0.65rem' }}>
                        {i + 1}
                      </div>
                      <div className="min-w-0">
                        {label && (
                          <p className="text-xs font-semibold truncate mb-0.5" style={{ color: '#E8C86A' }}>
                            {label}
                          </p>
                        )}
                        <div className="flex items-center gap-1.5">
                          <span className="mono text-xs tabular-nums" style={{ color: label ? 'var(--subtle)' : 'var(--ink-2)' }}>
                            {formatAddress(addr)}
                          </span>
                          <CopyButton text={addr} />
                        </div>
                      </div>
                    </div>
                    <div className="shrink-0 flex items-baseline gap-0.5">
                      <span className="display text-lg font-bold tabular-nums" style={{ color: 'var(--accent)' }}>{pct}</span>
                      <span className="text-xs font-medium" style={{ color: 'var(--muted)' }}>%</span>
                    </div>
                  </div>
                  <div className="mt-2.5 h-0.5 rounded-full overflow-hidden" style={{ background: 'rgba(255,255,255,0.08)' }}>
                    <div className="h-full rounded-full transition-all duration-700" style={{ width, background: 'rgba(245,200,66,0.55)' }} />
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {creator && creator !== '0x0000000000000000000000000000000000000000' && (
          <p className="mt-4 text-xs" style={{ color: 'var(--subtle)' }}>
            Created by <span className="mono">{formatAddress(creator)}</span>
          </p>
        )}
      </div>

      {/* Distribute */}
      <DistributeSection splitId={splitId} balance={balance} onDistributed={handleDistributed} />

      {/* Divider */}
      <div className="flex items-center gap-3">
        <div className="flex-1 h-px" style={{ background: 'rgba(245,200,66,0.10)' }} />
        <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--subtle)', letterSpacing: '0.1em' }}>Send</span>
        <div className="flex-1 h-px" style={{ background: 'rgba(245,200,66,0.10)' }} />
      </div>

      {/* Deposit */}
      <DepositSection splitId={splitId} onDeposited={handleDeposited} />
    </div>
  )
}
