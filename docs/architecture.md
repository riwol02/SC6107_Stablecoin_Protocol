# Architecture Documentation

## System Overview

The DSC Protocol is a decentralized, over-collateralized stablecoin system
inspired by MakerDAO. Users deposit crypto collateral (WETH, WBTC) and mint
DSC tokens pegged 1:1 to the US Dollar.

## Core Invariant

Core Formula: `total_collateral_value_USD >= total_DSC_supply`

The protocol enforces a 150% collateralization ratio. For every $100 of
DSC minted, $150 worth of collateral must be locked. This buffer ensures
solvency even during moderate market downturns.

## Contract Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User / Frontend                        │
└───────────────────────────┬─────────────────────────────────┘
                            │ ethers.js
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      DSCEngine.sol                           │
│                                                              │
│  depositCollateral()   ─────────────────────────────────────┤
│  mintDsc()             ─────────────────────────────────────┤──▶ DSCoin.sol (mint/burn)
│  redeemCollateral()    ─────────────────────────────────────┤
│  burnDsc()             ─────────────────────────────────────┤
│  liquidate()           ─────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ OracleLib (library)                                  │   │
│  │  staleCheckLatestRoundData() → Chainlink price feed  │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ┌──────────────────┴───────────────────┐
            ▼                                       ▼
  ┌─────────────────┐                    ┌──────────────────┐
  │ WETH (ERC-20)   │                    │ WBTC (ERC-20)    │
  │ collateral vault│                    │ collateral vault │
  └─────────────────┘                    └──────────────────┘
            │                                       │
            └──────────────────┬───────────────────┘
                               ▼
                  ┌────────────────────────┐
                  │  Chainlink Price Feeds │
                  │  ETH/USD  ·  BTC/USD   │
                  │  (3-hour stale guard)  │
                  └────────────────────────┘
```

## Key Parameters

| Parameter              | Value      | Description                              |
|------------------------|------------|------------------------------------------|
| Collateral ratio       | 150%       | Must hold $150 collateral per $100 DSC  |
| Liquidation threshold  | 150%       | Same as ratio — triggers liquidation     |
| Liquidation bonus      | 10%        | Reward for liquidators                   |
| Min health factor      | 1.0 (1e18) | Below 1.0 → liquidatable                |
| Oracle stale timeout   | 3 hours    | Reverts if feed not updated              |
| Max mint per tx        | 1,000,000  | DSC circuit breaker                      |

## Health Factor Formula

```
health_factor = (collateral_value_usd × 150 / 100) / dsc_minted

If dsc_minted == 0 → health_factor = ∞ (type(uint256).max)
```

Example:
- 10 ETH @ $2,000 = $20,000 collateral
- Minted: $5,000 DSC
- HF = ($20,000 × 1.5) / $5,000 = 6.0 (Healthy)

Crash scenario:
- ETH drops to $100 → collateral = $1,000
- HF = ($1,000 × 1.5) / $5,000 = 0.3 (Liquidatable)

## Liquidation Flow

```
Liquidator calls: liquidate(collateral, user, debtToCover)
    │
    ├── Check: user.healthFactor < 1.0 (else revert)
    ├── Calculate: tokenAmount = debtToCover / ETH_price
    ├── Add: bonus = tokenAmount × 10%
    ├── Transfer: (tokenAmount + bonus) collateral → liquidator
    ├── Burn: debtToCover DSC from liquidator
    └── Verify: user.healthFactor improved (else revert)
```

## Security Model

### Reentrancy Protection
All state-changing functions use `nonReentrant` modifier from OpenZeppelin.
State is updated before external calls (Checks-Effects-Interactions pattern).

### Oracle Security
- Chainlink feeds with 3-hour stale price check via `OracleLib`
- If any feed returns stale data, the entire transaction reverts
- Multiple collateral tokens with independent feeds

### Emergency Controls
- `Pausable` pattern: owner can pause all deposits/mints/liquidations
- In production, owner should be a multisig (Gnosis Safe)
- Timelock recommended for parameter changes

### Access Control
- `DSCoin` ownership transferred to `DSCEngine` at deployment
- Only `DSCEngine` can mint/burn DSC tokens
- Protocol parameters are immutable after deployment

## Storage Layout

```
DSCEngine:
  s_priceFeeds:           mapping(address => address)
  s_collateralDeposited:  mapping(address => mapping(address => uint256))
  s_DSCMinted:            mapping(address => uint256)
  s_collateralTokens:     address[]
```

No storage collisions (no proxies used — system is not upgradeable by design).
