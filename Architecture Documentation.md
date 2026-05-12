# Architecture Documentation

## System Design & Component Interaction

> SC6107: Blockchain Development Fundamentals (Part 2) DSC Protocol — Decentralized Stable Coin

------

## Table of Contents

1. [System Overview](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#1-system-overview)
2. [High-Level Architecture](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#2-high-level-architecture)
3. [Component Descriptions](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#3-component-descriptions)
4. [Component Interaction](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#4-component-interaction)
5. [Data Flow Diagrams](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#5-data-flow-diagrams)
6. [Storage Layout](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#6-storage-layout)
7. [Key Design Decisions](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#7-key-design-decisions)
8. [Deployment Architecture](https://claude.ai/chat/6f1dec31-e0af-4e6c-9270-8411fc02b7a3#8-deployment-architecture)

------

## 1. System Overview

The DSC Protocol is a three-layer decentralized stablecoin system:

```
┌─────────────────────────────────────────────────────┐
│  Layer 3 — Presentation                              │
│  React Frontend + ethers.js + MetaMask              │
├─────────────────────────────────────────────────────┤
│  Layer 2 — Protocol Logic                            │
│  DSCEngine.sol  ·  OracleLib.sol                    │
├─────────────────────────────────────────────────────┤
│  Layer 1 — Token & Oracle Infrastructure            │
│  DSCoin.sol  ·  WETH/WBTC  ·  Chainlink Feeds      │
└─────────────────────────────────────────────────────┘
```

**Core invariant the system enforces at all times:**

```
total_collateral_value_USD ≥ total_DSC_supply_USD
```

------

## 2. High-Level Architecture

```
                        ┌──────────────────────────────────────┐
                        │         User / Browser               │
                        │   MetaMask Wallet (EIP-1193)         │
                        └──────────────┬───────────────────────┘
                                       │ JSON-RPC
                        ┌──────────────▼───────────────────────┐
                        │        React Frontend                 │
                        │  ┌─────────────────────────────┐     │
                        │  │   useProtocol.js (Hook)     │     │
                        │  │   ethers.js v6              │     │
                        │  └──────────────┬──────────────┘     │
                        └─────────────────┼────────────────────┘
                                          │ Contract Calls
              ┌───────────────────────────▼──────────────────────────────┐
              │                    DSCEngine.sol                          │
              │                                                           │
              │  ┌─────────────────┐      ┌───────────────────────────┐  │
              │  │ Collateral Mgmt │      │    Health Factor Engine    │  │
              │  │                 │      │                           │  │
              │  │ depositCollat() │      │ _healthFactor(user)       │  │
              │  │ redeemCollat()  │      │ _revertIfHFBroken(user)   │  │
              │  └────────┬────────┘      └──────────┬────────────────┘  │
              │           │                          │                    │
              │  ┌────────▼────────┐      ┌──────────▼────────────────┐  │
              │  │   DSC Issuance  │      │    Liquidation Engine     │  │
              │  │                 │      │                           │  │
              │  │ mintDsc()       │      │ liquidate(collat,user,    │  │
              │  │ burnDsc()       │      │           debtToCover)    │  │
              │  └────────┬────────┘      └──────────┬────────────────┘  │
              │           │                          │                    │
              └───────────┼──────────────────────────┼────────────────────┘
                          │                          │
         ┌────────────────▼──────┐     ┌─────────────▼──────────────────┐
         │      DSCoin.sol       │     │         OracleLib.sol          │
         │                       │     │                                 │
         │  ERC-20 Stablecoin    │     │  staleCheckLatestRoundData()   │
         │  mint()  (onlyOwner)  │     │  Timeout: 3 hours              │
         │  burn()  (onlyOwner)  │     │                                 │
         └───────────────────────┘     └──────────────┬──────────────────┘
                                                      │
                                       ┌──────────────▼──────────────────┐
                                       │      Chainlink Price Feeds       │
                                       │                                  │
                                       │  ETH/USD  ·  BTC/USD            │
                                       │  (Sepolia Mainnet Feeds or       │
                                       │   MockV3Aggregator for testing)  │
                                       └──────────────────────────────────┘
```

------

## 3. Component Descriptions

### 3.1 DSCoin.sol

**Type:** ERC-20 Token Contract

The stablecoin token. Its supply is 100% controlled by `DSCEngine` — no public minting is possible.

| Property       | Value                           |
| -------------- | ------------------------------- |
| Token name     | Decentralized Stable Coin       |
| Symbol         | DSC                             |
| Decimals       | 18                              |
| Standard       | ERC-20 + ERC20Burnable          |
| Access control | `onlyOwner` (owner = DSCEngine) |

Key functions:

```solidity
function mint(address to, uint256 amount) external onlyOwner returns (bool)
function burn(uint256 amount) public override onlyOwner
```

**Ownership transfer at deployment:**

```
Deploy DSCoin → Deploy DSCEngine → DSCoin.transferOwnership(DSCEngine)
```

After this, only `DSCEngine` can ever mint or burn DSC.

------

### 3.2 DSCEngine.sol

**Type:** Core Protocol Contract (stateful)

The central engine that manages all protocol state. It holds all deposited collateral and enforces the health factor invariant on every operation.

| Property              | Value                              |
| --------------------- | ---------------------------------- |
| Collateral ratio      | 150%                               |
| Liquidation threshold | 150%                               |
| Liquidation bonus     | 10%                                |
| Min health factor     | 1.0 (1e18)                         |
| Max mint per tx       | 1,000,000 DSC                      |
| Inheritance           | ReentrancyGuard, Pausable, Ownable |

Key responsibilities:

- Accept and track collateral deposits per user per token
- Issue DSC tokens (via DSCoin.mint) when collateral is sufficient
- Enforce health factor checks after every state change
- Execute liquidations with bonus for liquidators
- Query Chainlink prices through OracleLib

------

### 3.3 OracleLib.sol

**Type:** Solidity Library (stateless)

A pure utility library used by `DSCEngine` to safely read Chainlink price feeds. It adds a staleness check that any price older than 3 hours triggers a protocol-wide revert.

```solidity
uint256 private constant TIMEOUT = 3 hours;

function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
    public view
    returns (uint80, int256, uint256, uint256, uint80)
{
    // Calls priceFeed.latestRoundData()
    // Reverts with OracleLib__StalePrice() if updatedAt > 3 hours ago
}
```

Why this matters: If Chainlink nodes go offline or return stale data, the protocol pauses itself automatically rather than operating on incorrect prices.

------

### 3.4 Frontend (React)

**Type:** Off-chain Web Application

A React single-page application that provides a user interface for all protocol operations.

| Component        | Responsibility                                     |
| ---------------- | -------------------------------------------------- |
| `App.jsx`        | Main dashboard, layout, panel routing              |
| `useProtocol.js` | All blockchain interactions (connect, read, write) |
| `contracts.js`   | ABI definitions for DSCEngine and ERC-20           |
| `index.css`      | Global styling with CSS variables (light/dark)     |

The `useProtocol` hook encapsulates:

- MetaMask connection and network switching
- Real-time account data fetching
- Transaction lifecycle (approve → execute → refresh)
- Error handling and loading states

------

### 3.5 Mock Contracts (Testing Only)

**Type:** Test Infrastructure

| Contract               | Replaces        | Purpose                   |
| ---------------------- | --------------- | ------------------------- |
| `MockERC20.sol`        | WETH / WBTC     | Mintable test tokens      |
| `MockV3Aggregator.sol` | Chainlink feeds | Controllable price oracle |

`MockV3Aggregator` allows tests to simulate:

- ETH price crashes (to trigger liquidations)
- Stale prices (to test oracle protection)
- Price updates mid-test (to verify health factor changes)

------

## 4. Component Interaction

### 4.1 Deposit Collateral & Mint DSC

```
User
 │
 ├─1─► Frontend: fills form (token=WETH, collateral=10, dsc=5000)
 │
 ├─2─► useProtocol: calls token.approve(DSCEngine, 10 WETH)
 │       └─► MetaMask: user signs Approve tx
 │
 ├─3─► useProtocol: calls DSCEngine.depositCollateralAndMintDsc(WETH, 10e18, 5000e18)
 │       └─► MetaMask: user signs main tx
 │
 └─4─► DSCEngine (on-chain execution):
         ├─ Checks: token allowed, amount > 0, not paused
         ├─ Effects: s_collateralDeposited[user][WETH] += 10e18
         ├─ Effects: s_DSCMinted[user] += 5000e18
         ├─ Checks: healthFactor(user) >= 1.0
         │    └─► OracleLib.staleCheckLatestRoundData(ETH/USD feed)
         │         └─► Chainlink: returns ($2000, timestamp)
         │    Health Factor = ($20,000 × 1.5) / $5,000 = 6.0 ✅
         ├─ Interact: WETH.transferFrom(user → DSCEngine)
         └─ Interact: DSCoin.mint(user, 5000e18)
```

### 4.2 Liquidation

```
Liquidator
 │
 ├─1─► Observes: user's ETH collateral crashed → HF < 1.0
 │
 ├─2─► Frontend: fills liquidate form (collateral=WETH, user=0x..., debt=5000)
 │
 ├─3─► useProtocol: calls DSCoin.approve(DSCEngine, 5000e18)
 │
 ├─4─► useProtocol: calls DSCEngine.liquidate(WETH, user, 5000e18)
 │
 └─5─► DSCEngine (on-chain execution):
         ├─ Checks: user.healthFactor < 1.0
         │    └─► OracleLib: fetches current ETH price
         ├─ Calculates:
         │    tokenAmountFromDebt = $5,000 / $900 = 5.555 WETH
         │    bonus               = 5.555 × 10%  = 0.555 WETH
         │    totalSeized         = 6.111 WETH
         ├─ Effects: s_collateralDeposited[user][WETH] -= 6.111 WETH
         ├─ Effects: s_DSCMinted[user] -= 5000e18
         ├─ Interact: WETH.transfer(liquidator, 6.111 WETH)
         ├─ Interact: DSCoin.transferFrom(liquidator → DSCEngine, 5000e18)
         ├─ Interact: DSCoin.burn(5000e18)
         └─ Checks: user.healthFactor improved ✅
```

### 4.3 Oracle Price Flow

```
DSCEngine.getUsdValue(WETH, 10e18)
 │
 └─► OracleLib.staleCheckLatestRoundData(ETH_USD_FEED)
      │
      └─► AggregatorV3Interface.latestRoundData()
           │
           └─► Chainlink Node Network
                └─► Returns: (roundId, 200000000000, startedAt, updatedAt, answeredInRound)
                              ↑ $2,000 with 8 decimals

      OracleLib checks: block.timestamp - updatedAt ≤ 3 hours
           ├─ OK  → returns price data
           └─ FAIL → revert OracleLib__StalePrice()

 DSCEngine: price = 200000000000 × 1e10 = 2000e18 (converted to 18 decimals)
            value = (2000e18 × 10e18) / 1e18 = 20000e18 = $20,000
```

### 4.4 Health Factor Calculation

```
DSCEngine._healthFactor(user)
 │
 ├─► _getAccountInformation(user)
 │    ├─ totalDscMinted = s_DSCMinted[user]
 │    └─ collateralValueInUsd = getAccountCollateralValue(user)
 │         └─ loops over s_collateralTokens[]
 │              └─ getUsdValue(token, s_collateralDeposited[user][token])
 │                   └─► OracleLib → Chainlink
 │
 └─► _calculateHealthFactor(totalDscMinted, collateralValueInUsd)
      │
      ├─ if totalDscMinted == 0 → return type(uint256).max (∞)
      │
      └─ collateralAdjusted = collateralValueInUsd × 150 / 100
         healthFactor = collateralAdjusted × 1e18 / totalDscMinted

Example:
  collateralValueInUsd = 20000e18 ($20,000)
  totalDscMinted       = 5000e18  ($5,000)
  collateralAdjusted   = 20000e18 × 150 / 100 = 30000e18
  healthFactor         = 30000e18 × 1e18 / 5000e18 = 6e18 (= 6.0)
```

------

## 5. Data Flow Diagrams

### 5.1 System State Transitions

```
                    ┌─────────────────────────────────────────────────┐
                    │                  USER POSITION                  │
                    └──────────────────────────┬──────────────────────┘
                                               │
                    ┌──────────────────────────▼──────────────────────┐
                    │              No Position (HF = ∞)               │
                    │      collateral = 0, dscMinted = 0              │
                    └──┬───────────────────────────────────────────────┘
                       │
                       │  depositCollateral()
                       │  + mintDsc()
                       ▼
                    ┌──────────────────────────────────────────────────┐
                    │              Active Position                      │
                    │         HF = collateral × 1.5 / debt             │
                    └──┬──────────────────────────────────────────┬────┘
                       │                                          │
                       │  Price drops                             │  burnDsc()
                       │  HF → < 1.0                             │  + redeemCollateral()
                       ▼                                          ▼
                    ┌─────────────────────┐            ┌──────────────────────┐
                    │  Undercollateralized │            │   Position Closed    │
                    │     HF < 1.0        │            │     HF = ∞           │
                    └──────────┬──────────┘            └──────────────────────┘
                               │
                               │  liquidate()
                               ▼
                    ┌─────────────────────┐
                    │  Partially/Fully    │
                    │  Liquidated         │
                    │  Debt reduced       │
                    └─────────────────────┘
```

### 5.2 Token Flow

```
     User Wallet                DSCEngine                 DSCoin Supply
         │                          │                          │
         │──── WETH (approve) ─────►│                          │
         │──── WETH (deposit) ──────►│                          │
         │                          │──── mint(user, amt) ────►│
         │◄─── DSC (minted) ────────────────────────────────────│
         │                          │                          │
         │   [time passes, user wants to close position]        │
         │                          │                          │
         │──── DSC (approve) ──────►│                          │
         │──── DSC (burn) ─────────►│──── burn(amt) ──────────►│
         │◄─── WETH (returned) ─────│                          │
         │                          │                          │
         │   [liquidation scenario]                             │
         │                          │                          │
Liquidator──── DSC (approve) ──────►│                          │
Liquidator──── liquidate() ────────►│──── burn(debt) ─────────►│
Liquidator◄─── WETH + 10% bonus ───│                          │
```

------

## 6. Storage Layout

### DSCEngine Storage Variables

```
Slot 0:  _status (ReentrancyGuard)
Slot 1:  _paused (Pausable)
Slot 2:  _owner  (Ownable — packed with _paused)

Mapping slot A:  s_priceFeeds
  keccak256(token . slotA) → priceFeed address

Mapping slot B:  s_collateralDeposited
  keccak256(user . slotB) → inner mapping slot
  keccak256(token . innerSlot) → uint256 amount

Mapping slot C:  s_DSCMinted
  keccak256(user . slotC) → uint256 amount

Dynamic array slot D:  s_collateralTokens
  slot D → length
  keccak256(D) + i → s_collateralTokens[i]

Immutable (bytecode):  i_dsc → DSCoin address
```

No storage collisions exist because the system does not use any proxy pattern. The contract is deployed directly and its storage layout is fixed permanently at deployment.

### DSCoin Storage Variables

```
Inherited from ERC20:
  Slot 0: _balances mapping
  Slot 1: _allowances mapping
  Slot 2: _totalSupply
  Slot 3: _name (string)
  Slot 4: _symbol (string)

Inherited from Ownable:
  Slot 5: _owner
```

------

## 7. Key Design Decisions

### 7.1 No Upgradeability

**Decision:** Deploy immutable contracts with no proxy pattern.

**Rationale:**

- Eliminates admin key risk — no one can change protocol logic
- Users can audit and trust the exact deployed bytecode permanently
- Simplifies security analysis (no storage collision risks)
- Aligns with the principle of "code is law"

**Trade-off:** Bugs cannot be patched without deploying a new protocol version and migrating user funds.

------

### 7.2 Exogenous Collateral Only

**Decision:** Accept only WETH and WBTC as collateral — never DSC itself.

**Rationale:**

- Eliminates circular dependency between collateral value and stablecoin value
- When DSC price drops, WETH/WBTC prices are unaffected → no death spiral
- Contrast with UST/LUNA: LUNA was both the collateral and the stability mechanism

**Trade-off:** Lower capital efficiency compared to endogenous models (but far safer).

------

### 7.3 150% Collateral Ratio

**Decision:** Require 150% collateral (not 110% like Liquity, not 200% like early MakerDAO).

**Rationale:**

- 50% buffer gives liquidators time to act even in fast-moving markets
- 110% ratios (like Liquity) require an instant-liquidation stability pool to be safe
- 200% ratios are unnecessarily capital-inefficient
- 150% is the industry standard for protocols without stability pools

------

### 7.4 10% Liquidation Bonus

**Decision:** Give liquidators a 10% bonus on seized collateral.

**Rationale:**

- Creates economic incentive for anyone to liquidate unhealthy positions
- Permissionless — no whitelisted liquidator required
- 10% is enough to cover gas costs and provide profit even during high gas periods
- If bonus were too high, it would punish borrowers unnecessarily

------

### 7.5 Chainlink as Sole Oracle

**Decision:** Use Chainlink price feeds as the only price source, protected by a 3-hour staleness check.

**Rationale:**

- Chainlink is the most battle-tested decentralized oracle network
- 3-hour timeout is conservative (most feeds update every ~20 minutes)
- If Chainlink fails, the protocol pauses itself rather than operating on stale prices

**Trade-off:** Single oracle dependency. Production recommendation: add TWAP from Uniswap as a secondary validation source.

------

## 8. Deployment Architecture

### Local Development (Anvil)

```
Developer Machine
├── anvil (local EVM, chainId=31337)
│    ├── MockERC20 (WETH)        0xe7f1725...
│    ├── MockERC20 (WBTC)        0x9fE4673...
│    ├── MockV3Aggregator (ETH)  0xCf7Ed3A...  ← $2,000/ETH
│    ├── MockV3Aggregator (BTC)  0xDc64a14...  ← $60,000/BTC
│    ├── DSCoin                  0x5FC8d32...
│    └── DSCEngine               0x0165878...
│
├── React Frontend (localhost:3000)
│    └── MetaMask → Anvil RPC (http://127.0.0.1:8545)
│
└── Foundry Test Suite
     └── forge test → spins up isolated EVM per test
```

### Sepolia Testnet

```
Sepolia Network (chainId=11155111)
├── Chainlink ETH/USD Feed  0x694AA17...  ← Real feed
├── Chainlink BTC/USD Feed  0x1b44F35...  ← Real feed
├── Sepolia WETH            0xdd13E55...
├── Sepolia WBTC            0x8f3Cf7a...
├── DSCoin                  0xB952a19...  (deployed by team)
└── DSCEngine               0x7Bca20d...  (deployed by team)

React Frontend
└── MetaMask → Sepolia RPC (Infura / Alchemy)
```

### Deployment Sequence

```
1. Deploy OracleLib (library — linked into DSCEngine bytecode)
2. Deploy MockERC20 (WETH)           ← Anvil only
3. Deploy MockERC20 (WBTC)           ← Anvil only
4. Deploy MockV3Aggregator (ETH/USD) ← Anvil only
5. Deploy MockV3Aggregator (BTC/USD) ← Anvil only
6. Deploy DSCoin
7. Deploy DSCEngine(
     tokenAddresses  = [WETH, WBTC],
     priceFeedAddresses = [ETH/USD, BTC/USD],
     dscAddress = DSCoin
   )
8. DSCoin.transferOwnership(DSCEngine)
   → From this point, only DSCEngine can mint/burn DSC
```

------

*Document version: 1.0 | Last updated: 2026* *For security analysis see: `docs/security-analysis.md`* *For gas optimization details see: `docs/gas-optimization.md`*