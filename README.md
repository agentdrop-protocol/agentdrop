# AgentDrop

**Free claim pools, gated by Agent ID.** Permissionless claim-pool infrastructure on BNB Chain, built for the Binance Wallet × BNB Chain **Agent ID Hackathon**.

Anyone can create a pool of ERC-20 tokens — or a mint-on-claim NFT pool — that only **SPACE ID Agent ID** holders can claim from, once per address per pool. The gate is checked on-chain against the official Agent ID contract, so eligibility needs no allowlists, screenshots, or trust.

## Live on BNB Chain mainnet

| Contract | Address |
| --- | --- |
| AgentDrop | `0x35E0f6e1F729a03B34d1f25Fa20725E1c95C6A71` |
| PioneerNFT | `0xd250D888152F7155854360456F218B94a4dA7995` |
| SPACE ID Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |

Both contracts are verified on Sourcify with an **exact match**. Demo pool **#0** (Pioneer NFT, 100 claims) is live until 2026-12-08 05:00 UTC — try it from the project page (GitHub Pages, `docs/`).

## How it works

- **Create** — `createTokenPool(token, amountPerClaim, maxClaims, start, end)` deposits the full pool amount up front; `createNftPool(nft, maxClaims, start, end)` creates a mint-on-claim pool.
- **Claim** — `claim(poolId)` checks `AgentId.balanceOf(claimer) > 0`, enforces one claim per address per pool and the pool window, then transfers the tokens or mints the NFT. The claimer pays only their own gas.
- **Reclaim** — after a pool ends, its creator can recover whatever was never claimed. Nobody else can touch pool funds.

## Design choices

- **No owner, no admin.** `AgentDrop` deliberately has no owner and no privileged functions; the Agent ID registry address is immutable. Once a pool exists, its rules cannot change.
- **One Agent ID = one claim.** Agent ID is non-transferable and capped at one per user, so per-address claim limits are per-person limits.
- **Mint-on-claim NFTs.** `PioneerNFT` can only be minted through AgentDrop claims (its minter is set once, to the AgentDrop contract), so supply can never exceed claimed demand.

## Security

An internal security review (2026-11-21) found no Critical or High issues. Known, accepted limitations: non-standard ERC-20s (fee-on-transfer, rebasing) can mis-account a token pool — pool creators should use standard tokens; NFT pools are unaffected.

## Tests

14 tests, all passing — 9 unit tests plus 5 fork tests against the real SPACE ID Agent ID contract on BNB Chain (including: a real holder claims and receives a Pioneer NFT; a non-holder's claim reverts; a double claim reverts).

```bash
forge test            # unit suite
BSC_RPC_URL=<bsc rpc> forge test --match-contract AgentDropForkTest
```

## Layout

- `src/AgentDrop.sol` — the pool contract (no owner/admin by design)
- `src/PioneerNFT.sol` — the commemorative ERC-721, minted only via claims
- `script/Deploy.s.sol` — deploy script (PioneerNFT → AgentDrop → setMinter, in that order)
- `docs/` — the static claim page (wallet-connect, eligibility check, claim)
- `deployment-56.json` — mainnet deployment record (addresses + tx hashes)

## License

MIT
