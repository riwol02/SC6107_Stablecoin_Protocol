# Security Analysis

## Threat Model

### Assets at Risk
- Collateral tokens (WETH, WBTC) held in DSCEngine
- DSC token supply (value backed by collateral)
- Protocol solvency (core invariant: collateral ≥ DSC supply)

---

## Vulnerability Analysis

### 1. Reentrancy Attacks

**Risk:** `depositCollateral`, `redeemCollateral`, `liquidate` all make
external ERC-20 calls. A malicious token could re-enter the contract.

**Mitigation:**
- `nonReentrant` modifier on all state-changing functions (OpenZeppelin `ReentrancyGuard`)
- Checks-Effects-Interactions: storage updated *before* token transfers
- `SafeERC20` used for all transfers (prevents silent failures)

**Status: ✅ Mitigated**

---

### 2. Oracle Manipulation / Stale Prices

**Risk:** If Chainlink feed returns stale or manipulated prices, attackers
can mint DSC with insufficient collateral or avoid liquidation.

**Mitigation:**
- `OracleLib.staleCheckLatestRoundData()` reverts if price > 3 hours old
- Multi-oracle validation recommended for production (Chainlink + TWAP)
- Emergency pause available if oracle is compromised

**Residual risk:** Single oracle dependency. Chainlink itself could be
manipulated on low-liquidity chains. Mitigation: use `TWAP` or `median`
of multiple oracles.

**Status: ✅ Core mitigation applied, ⚠️ single oracle risk remains**

---

### 3. Liquidation Failure / Bad Debt

**Risk:** If ETH price crashes faster than liquidators can act, positions
become underwater (collateral < DSC debt). This creates bad debt.

**Mitigation:**
- 150% collateral ratio provides 50% buffer above minimum
- 10% liquidation bonus incentivizes fast liquidation
- `liquidate()` reverts if health factor doesn't improve
- In production: keeper bots monitor health factors 24/7

**Residual risk:** Flash crash of >33% could outpace liquidators.
Advanced: implement stability pool (like Liquity) for instant liquidation.

**Status: ✅ Economically incentivized, ⚠️ flash crash edge case**

---

### 4. Integer Overflow / Underflow

**Risk:** Arithmetic errors could allow minting more DSC than allowed,
or incorrectly track collateral balances.

**Mitigation:**
- Solidity 0.8.x built-in overflow/underflow protection (reverts on error)
- No `unchecked` blocks used
- `s_collateralDeposited[from][token] -= amount` will revert on underflow
  if user tries to redeem more than deposited

**Status: ✅ Fully mitigated by compiler**

---

### 5. Front-Running / MEV

**Risk:** Liquidation transactions could be front-run by MEV bots.
DSC minting could be sandwiched if price changes are predictable.

**Mitigation:**
- Liquidations are permissionless — MEV bots competing actually benefits
  the protocol (faster liquidation = more solvency)
- No slippage risk in minting (price read at execution time)
- For production: consider Flashbots Protect for sensitive operations

**Status: ✅ Acceptable (MEV on liquidations is protocol-beneficial)**

---

### 6. Access Control

**Risk:** Unauthorized minting of DSC could inflate supply and break the peg.

**Mitigation:**
- `DSCoin.mint()` is `onlyOwner` — ownership transferred to `DSCEngine`
- `DSCEngine.pause()` is `onlyOwner` — owner should be multisig in production
- No admin function to change price feeds or thresholds post-deployment

**Status: ✅ Mitigated**

---

### 7. Death Spiral

**Risk:** DSC price drops → liquidations → more price drops → protocol collapse
(similar to UST/Luna).

**Mitigation:**
- DSC is *exogenously* collateralized (WETH/WBTC ≠ DSC)
- Collateral is real external assets, not the protocol's own token
- 150% over-collateralization means collateral must drop 33% before risk
- This design matches DAI (battle-tested) rather than UST (algorithmic)

**Status: ✅ Structurally resistant by design**

---

## Static Analysis Results (Slither)

Run: `slither contracts/src/ --solc-remaps "@openzeppelin=lib/openzeppelin-contracts @chainlink=lib/chainlink"`

Expected findings and resolutions:

| Finding | Severity | Resolution |
|---------|----------|------------|
| `reentrancy-eth` | High | `nonReentrant` applied |
| `uninitialized-local` | Medium | All locals initialized |
| `calls-loop` | Low | Unavoidable in `getAccountCollateralValue` — bounded array |
| `timestamp` | Low | Used only for stale price check (acceptable) |
| `assembly` | Informational | None used |

---

## Audit Recommendations for Production

1. **Replace single oracle with multi-oracle median** (Chainlink + Uniswap TWAP)
2. **Transfer ownership to Gnosis Safe multisig** (3-of-5 minimum)
3. **Add timelock (48h) for emergency pause** to prevent admin abuse
4. **Implement stability pool** for instant liquidation of large positions
5. **Add circuit breaker on collateral ratio** — auto-pause if ratio drops below 120%
6. **Formal verification** of health factor and liquidation arithmetic
7. **Bug bounty program** before mainnet launch
