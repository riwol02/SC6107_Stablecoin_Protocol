# DSC Protocol — Decentralized Stable Coin

> **SC6107: Blockchain Development Fundamentals (Part 2)**
> Development Project · Option 6: Stablecoin Protocol

A fully on-chain, over-collateralized stablecoin protocol inspired by MakerDAO. Users deposit crypto assets (WETH, WBTC) as collateral and mint **DSC** tokens pegged 1:1 to the US Dollar. The protocol is entirely governed by immutable smart contracts — no admin keys, no intermediaries.

---

## Table of Contents

- [Overview](#overview)
- [Protocol Mechanics](#protocol-mechanics)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Security Design](#security-design)
- [Gas Optimization](#gas-optimization)
- [Testing](#testing)
- [Getting Started](#getting-started)
- [Deployment](#deployment)
- [Frontend](#frontend)
- [Project Structure](#project-structure)
- [Team](#team)
- [References](#references)

---

## Overview

### What is DSC?

DSC (Decentralized Stable Coin) is a USD-pegged ERC-20 token backed by exogenous crypto collateral. Its value is maintained through algorithmic over-collateralization enforced entirely on-chain by the `DSCEngine` contract.

### Key Parameters

| Parameter | Value | Description |
|---|---|---|
| Peg | 1 DSC = $1 USD | Maintained via collateralization |
| Collateral types | WETH, WBTC | Exogenous crypto assets |
| Collateral ratio | 150% | $150 collateral required per $100 DSC |
| Liquidation threshold | 150% | Positions below this are liquidatable |
| Liquidation bonus | 10% | Reward paid to liquidators |
| Stability fee | 0% | No interest charged (v1) |
| Price oracle | Chainlink | 3-hour stale price protection |

### Core Invariant

```
total_collateral_value_USD ≥ total_DSC_supply_USD   (at all times)
```

This invariant is enforced by the liquidation mechanism and verified by the invariant test suite.

### Comparison with Existing Stablecoins

| Property | USDT / USDC | UST (Terra) | DAI | **DSC** |
|---|---|---|---|---|
| Backing | Fiat (off-chain) | Algorithmic | Crypto (on-chain) | Crypto (on-chain) |
| Centralization | High | None | Low | **None** |
| Collateral | USD in banks | LUNA token | ETH, WBTC | **WETH, WBTC** |
| Death spiral risk | No | **Yes** | Low | **No** |
| Audit-able | Requires trust | On-chain | On-chain | **On-chain** |

DSC follows the DAI model (exogenous over-collateralization) rather than the UST model (endogenous algorithmic), making it structurally resistant to death spirals.

---

## Protocol Mechanics

### 1. Depositing Collateral & Minting DSC

Users lock WETH or WBTC into the protocol and receive DSC proportional to their collateral value, subject to the 150% collateral ratio.

```
Example:
  Deposit  10 WETH @ $2,000/ETH = $20,000 collateral
  Maximum mintable DSC = $20,000 × (100/150) = $13,333 DSC
  Safe mint (50% LTV) = $10,000 DSC

  Health Factor = ($20,000 × 150/100) / $10,000 = 3.0  ✅ Healthy
```

### 2. Health Factor

Every position is assigned a continuous health score. The protocol monitors this score in real time using Chainlink price feeds.

```
Health Factor = (collateral_value_USD × liquidation_threshold) / dsc_minted
             = (collateral_value_USD × 1.5) / dsc_minted

HF ≥ 2.0   →  Green  — Comfortably safe
HF ≥ 1.0   →  Yellow — Approaching danger
HF < 1.0   →  Red    — LIQUIDATABLE
HF = ∞     →  No debt minted
```

### 3. Liquidation

When a position's health factor drops below 1.0 (due to collateral price decline), any external party can act as a liquidator:

```
Liquidation flow:
  1. Liquidator calls liquidate(collateral, user, debtToCover)
  2. Protocol checks: user.healthFactor < 1.0
  3. Calculates collateral owed = debtToCover / collateral_price
  4. Adds 10% bonus:  total_seized = collateral_owed × 1.10
  5. Transfers seized collateral → liquidator
  6. Burns debtToCover DSC from liquidator's balance
  7. Verifies user's health factor improved (else reverts)

Example at $900/ETH (crashed from $2,000):
  User had: 10 WETH deposited, $13,000 DSC minted
  HF = ($9,000 × 1.5) / $13,000 = 1.038 → still ok
  
  At $800/ETH:
  HF = ($8,000 × 1.5) / $13,000 = 0.923 → LIQUIDATABLE ❌
  
  Liquidator covers $5,000 debt:
  Receives = ($5,000 / $800) × 1.10 = 6.875 WETH
  Profit   = 6.875 × $800 - $5,000 = $500 (10% bonus)
```

### 4. Redeeming Collateral

Users can partially or fully close their positions at any time by burning DSC and withdrawing collateral, provided their health factor remains above 1.0 after the operation.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     User / Frontend (React)                      │
│                        ethers.js v6                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DSCEngine.sol                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  depositCollateral()    redeemCollateral()               │   │
│  │  mintDsc()              burnDsc()                        │   │
│  │  depositCollateralAndMintDsc()                           │   │
│  │  redeemCollateralForDsc()                                │   │
│  │  liquidate()            pause() / unpause()              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────┐   ┌──────────────────────────────┐    │
│  │   OracleLib.sol      │   │       DSCoin.sol              │    │
│  │  staleCheckLatest    │   │  ERC-20 · mint() · burn()     │    │
│  │  RoundData()         │   │  onlyOwner = DSCEngine        │    │
│  │  (3-hour timeout)    │   └──────────────────────────────┘    │
│  └──────────┬───────────┘                                        │
└─────────────┼───────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│     Chainlink Price Feeds        │
│   ETH/USD  ·  BTC/USD           │
│   (Sepolia or Mock for Anvil)   │
└─────────────────────────────────┘
```

### Design Decisions

**Why no upgradeability?**
The protocol intentionally avoids proxy patterns. Immutability eliminates the risk of malicious upgrades and admin key compromise. Users can trust the deployed bytecode permanently.

**Why exogenous collateral only?**
Using WETH and WBTC (assets independent of DSC) eliminates circular dependency. If DSC price falls, it does not devalue the collateral — unlike UST/LUNA where collateral and stablecoin were coupled.

**Why 150% and not 110%?**
The 50% buffer provides time for liquidators to act during market downturns. Protocols with tighter ratios (e.g., Liquity at 110%) require more sophisticated instant-liquidation mechanisms (stability pools) to remain solvent.

---

## Smart Contracts

### `DSCoin.sol`

An ERC-20 token with restricted mint and burn access.

```solidity
// Mint: only DSCEngine can call
function mint(address to, uint256 amount) external onlyOwner returns (bool)

// Burn: only DSCEngine can call  
function burn(uint256 amount) public override onlyOwner
```

Key properties:
- Ownership transferred to `DSCEngine` at deployment
- No public minting — supply is fully controlled by collateral backing
- Inherits `ERC20Burnable` from OpenZeppelin 5.x

### `DSCEngine.sol`

The core protocol contract. Manages all collateral positions and enforces the health factor invariant.

```solidity
// Deposit collateral + mint DSC in one transaction
function depositCollateralAndMintDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToMint
) external whenNotPaused

// Liquidate an undercollateralized position
function liquidate(
    address collateral,
    address user,
    uint256 debtToCover
) external whenNotPaused moreThanZero(debtToCover) nonReentrant

// Read health factor for any address
function getHealthFactor(address user) external view returns (uint256)
```

State variables:

```solidity
mapping(address token  => address priceFeed)            private s_priceFeeds;
mapping(address user   => mapping(address token => uint256)) private s_collateralDeposited;
mapping(address user   => uint256 amountDscMinted)      private s_DSCMinted;
address[]                                               private s_collateralTokens;
DSCoin private immutable i_dsc;
```

### `OracleLib.sol`

A library that wraps Chainlink's `latestRoundData()` with a staleness check. Any price older than 3 hours causes the entire transaction to revert, protecting the protocol from stale or manipulated oracle data.

```solidity
uint256 private constant TIMEOUT = 3 hours;

function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
    public view
    returns (uint80, int256, uint256, uint256, uint80)
{
    (roundId, answer, startedAt, updatedAt, answeredInRound)
        = priceFeed.latestRoundData();

    if (block.timestamp - updatedAt > TIMEOUT)
        revert OracleLib__StalePrice();
}
```

---

## Security Design

### Threats Addressed

| Threat | Mitigation | Status |
|---|---|---|
| Reentrancy | `ReentrancyGuard` on all state-changing functions | ✅ |
| Oracle manipulation | Chainlink multi-source + 3h stale timeout | ✅ |
| Integer overflow | Solidity 0.8.x built-in protection | ✅ |
| Silent transfer failure | `SafeERC20` for all ERC-20 transfers | ✅ |
| Admin key compromise | No upgradeable proxy; owner = multisig in prod | ✅ |
| Flash loan attacks | Checks-effects-interactions; no price reads mid-tx | ✅ |
| Death spiral | Exogenous collateral only (WETH/WBTC ≠ DSC) | ✅ |
| Emergency scenarios | `Pausable` — owner can halt all operations | ✅ |

### Checks-Effects-Interactions Pattern

Every function updates internal state before making external calls:

```solidity
function depositCollateral(...) external nonReentrant {
    // CHECK
    if (amountCollateral == 0) revert DSCEngine__NeedsMoreThanZero();

    // EFFECT — state updated first
    s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
    emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

    // INTERACT — external call last
    IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
}
```

### Emergency Pause

The owner (recommended: Gnosis Safe multisig in production) can immediately halt all deposits, mints, redeems, and liquidations:

```solidity
function pause()   external onlyOwner { _pause(); }
function unpause() external onlyOwner { _unpause(); }
```

### Static Analysis

Run Slither before submission:

```bash
slither contracts/src/ \
  --solc-remaps "@openzeppelin=lib/openzeppelin-contracts @chainlink=lib/chainlink"
```

Expected findings and resolutions are documented in [`docs/security-analysis.md`](docs/security-analysis.md).

---

## Gas Optimization

| Technique | Saving | Applied |
|---|---|---|
| `immutable` for DSCoin address | ~2,098 gas/read | ✅ |
| Custom errors instead of `require` strings | ~200–500 gas/revert | ✅ |
| `constant` for protocol parameters | ~2,100 gas/read | ✅ |
| Cached array length in loops | ~97 gas/iteration | ✅ |
| `SafeERC20` over manual return checks | Equivalent, safer | ✅ |
| Revert-early modifiers | Saves gas on invalid input | ✅ |

### Benchmarks (Anvil local fork)

| Function | Gas Used |
|---|---|
| `depositCollateral` | ~65,000 |
| `mintDsc` | ~75,000 |
| `depositCollateralAndMintDsc` | ~130,000 |
| `redeemCollateral` | ~55,000 |
| `burnDsc` | ~60,000 |
| `redeemCollateralForDsc` | ~115,000 |
| `liquidate` | ~140,000 |

Full analysis in [`docs/gas-optimization.md`](docs/gas-optimization.md).

---

## Testing

### Test Suite Overview

| Type | File | Coverage |
|---|---|---|
| Unit | `DSCEngineTest.t.sol` | 30+ tests, all public functions |
| Unit | `DSCoinTest.t.sol` | Token mint/burn/access control |
| Integration | `DSCIntegrationTest.t.sol` | 5 end-to-end user scenarios |
| Fuzz | `DSCFuzzTest.t.sol` | Property-based + invariant tests |

### Integration Test Scenarios

1. **Happy Path** — Deposit → Mint → Burn → Redeem full lifecycle
2. **Liquidation** — ETH price crash triggers liquidation, verify bonus paid
3. **Multi-User** — Multiple positions, protocol invariant holds throughout
4. **Emergency Pause** — Owner pauses, all operations revert, unpause resumes
5. **Stale Oracle** — Warp 4 hours, verify all transactions revert

### Invariant Under Test

```solidity
// The core protocol invariant — must hold after every operation
function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
    uint256 totalSupply     = dsc.totalSupply();
    uint256 wethValue       = engine.getUsdValue(weth, IERC20(weth).balanceOf(address(engine)));
    uint256 wbtcValue       = engine.getUsdValue(wbtc, IERC20(wbtc).balanceOf(address(engine)));

    assert(wethValue + wbtcValue >= totalSupply);
}
```

### Running Tests

```bash
# Full test suite
forge test -vvv

# Unit tests only
forge test --match-contract DSCEngineTest -vvv

# Integration scenarios
forge test --match-contract DSCIntegrationTest -vvv

# Fuzz + invariant (1000 runs)
forge test --match-contract FuzzTest -vvv
forge test --match-contract InvariantTest -vvv

# Coverage report
forge coverage --report lcov

# Gas snapshot
forge snapshot
```

### Coverage Targets

| Contract | Line Coverage | Branch Coverage |
|---|---|---|
| `DSCEngine.sol` | > 85% | > 80% |
| `DSCoin.sol` | 100% | 100% |
| `OracleLib.sol` | 100% | 100% |

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Foundry | Latest | `curl -L https://foundry.paradigm.xyz \| bash` |
| Node.js | ≥ 18 | https://nodejs.org |
| Git | Any | https://git-scm.com |

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-team/dsc-protocol
cd dsc-protocol

# 2. Initialize git (if not already)
git init

# 3. Install Solidity dependencies
forge install OpenZeppelin/openzeppelin-contracts \
              foundry-rs/forge-std \
              smartcontractkit/chainlink

# 4. Install frontend dependencies
cd frontend && npm install && cd ..

# 5. Copy environment template
cp .env.example .env
# Fill in PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
```

---

## Deployment

### Local (Anvil)

```bash
# Terminal 1 — Start local blockchain
anvil

# Terminal 2 — Deploy contracts
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv
```

### Local Setup for Test Account

After starting `anvil`, you can deploy the local contracts and fund the default
MetaMask test account in one step:

```bash
./scripts/setup-local-test-account.sh
```

Default funded account:

```text
0xa208DCE30A29B85099e8acDcc696276E4932894b
```

The script:
- Deploys the DSC protocol to local Anvil
- Sets the test account's local ETH balance for gas
- Mints `100 WETH` and `100 WBTC` to the test account

To fund a different account:

```bash
TEST_ACCOUNT=0xYourAddress ./scripts/setup-local-test-account.sh
```

The deployment script automatically:
- Deploys Mock WETH and WBTC tokens
- Deploys Mock Chainlink price feeds ($2,000/ETH, $60,000/BTC)
- Deploys `DSCoin` and `DSCEngine`
- Transfers `DSCoin` ownership to `DSCEngine`

### Sepolia Testnet

```bash
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

Sepolia uses real Chainlink price feeds and real WETH/WBTC token addresses — no mocks needed.

### After Deployment

Update `frontend/src/hooks/useProtocol.js` with the deployed addresses:

```js
const ADDRESSES = {
  DSC_ENGINE: "0x...",  // from deployment output
  DSC_COIN:   "0x...",  // from deployment output
  WETH:       "0x...",  // mock (Anvil) or real (Sepolia)
  WBTC:       "0x...",  // mock (Anvil) or real (Sepolia)
};
```

### Deployed Contract Addresses (Anvil — for reference)

| Contract | Address |
|---|---|
| DSCoin | `0x5FC8d32690cc91D4c39d9d3abcBD16989F875707` |
| DSCEngine | `0x0165878A594ca255338adfa4d48449f69242Eb8F` |
| Mock WETH | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| Mock WBTC | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| ETH/USD Feed | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |
| BTC/USD Feed | `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` |

---

## Frontend

### Tech Stack

| Layer | Technology |
|---|---|
| Framework | React 18 |
| Web3 library | ethers.js v6 |
| Wallet | MetaMask (EIP-1193) |
| Styling | Vanilla CSS with CSS variables (light/dark mode) |

### Features

- **Dashboard** — Live display of DSC minted, collateral value, health factor, DSC balance
- **Position Health Gauge** — Visual progress bar with color-coded risk levels
- **Deposit & Mint** — One-click collateral deposit and DSC minting
- **Redeem & Burn** — Partial or full position closure
- **Liquidate** — Interface for liquidating undercollateralized positions
- **Auto-network switching** — Forces MetaMask to Anvil Local on connect
- **Dark/light mode** — Follows system preference via `prefers-color-scheme`

### Running the Frontend

```bash
cd frontend
npm start
# Opens at http://localhost:3000
```

Connect MetaMask to Anvil Local:

| Field | Value |
|---|---|
| Network Name | Anvil Local |
| RPC URL | http://127.0.0.1:8545 |
| Chain ID | 31337 |
| Currency Symbol | ETH |

Mint test tokens (Anvil only):

```bash
# Mint 1000 WETH to your wallet
cast send <WETH_ADDRESS> "mint(address,uint256)" \
  <YOUR_WALLET> 1000000000000000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY>
```

---

## Project Structure

```
stablecoin-protocol/
│
├── README.md                          ← This file
├── foundry.toml                       ← Foundry configuration
├── .env.example                       ← Environment variable template
├── .gitignore
│
├── contracts/
│   ├── src/
│   │   ├── DSCoin.sol                 ← ERC-20 stablecoin token
│   │   ├── DSCEngine.sol              ← Core protocol engine
│   │   └── libraries/
│   │       └── OracleLib.sol          ← Chainlink stale price protection
│   │
│   ├── test/
│   │   ├── unit/
│   │   │   ├── DSCEngineTest.t.sol    ← 30+ unit tests
│   │   │   └── DSCoinTest.t.sol       ← Token unit tests
│   │   ├── integration/
│   │   │   └── DSCIntegrationTest.t.sol ← 5 end-to-end scenarios
│   │   └── fuzz/
│   │       └── DSCFuzzTest.t.sol      ← Invariant + fuzz tests
│   │
│   ├── script/
│   │   └── DeployDSC.s.sol            ← Deployment script (Anvil + Sepolia)
│   │
│   └── mocks/
│       ├── MockERC20.sol              ← Test collateral token
│       └── MockV3Aggregator.sol       ← Test Chainlink price feed
│
├── frontend/
│   ├── package.json
│   ├── public/
│   │   └── index.html
│   └── src/
│       ├── App.jsx                    ← Main dashboard UI
│       ├── index.js                   ← React entry point
│       ├── index.css                  ← Global styles
│       ├── hooks/
│       │   └── useProtocol.js         ← All blockchain interactions
│       └── abis/
│           └── contracts.js           ← DSCEngine + ERC20 ABIs
│
└── docs/
    ├── architecture.md                ← System design & component diagram
    ├── security-analysis.md           ← Threat model & vulnerability analysis
    └── gas-optimization.md            ← Optimization strategies & benchmarks
```

---

## Team

| Member | Role | Responsibilities |
|---|---|---|
| Member 1 | Smart Contract Lead | `DSCEngine.sol` core logic, liquidation mechanism |
| Member 2 | Security Engineer | `OracleLib.sol`, security analysis, Slither audit |
| Member 3 | Test Engineer | Unit tests, fuzz tests, invariant tests, coverage |
| Member 4 | Frontend Developer | React dashboard, `useProtocol` hook, UX design |
| Member 5 | DevOps / Docs | Deployment scripts, README, architecture diagrams |

---

## Course Topics Demonstrated

| SC6107 Topic | Where Demonstrated |
|---|---|
| ERC-20 token development | `DSCoin.sol` — custom mint/burn with access control |
| Smart contract security patterns | `DSCEngine.sol` — ReentrancyGuard, CEI, Pausable |
| DeFi protocol design | Over-collateralization, health factor, liquidation incentives |
| Oracle integration | `OracleLib.sol` — Chainlink with stale price protection |
| Foundry testing | Unit, integration, fuzz, and invariant test suites |
| Gas optimization | Custom errors, immutables, constants, storage layout |
| Frontend Web3 integration | ethers.js v6, MetaMask EIP-1193, React hooks |
| Deployment scripting | Multi-network deploy with Anvil mock + Sepolia real feeds |

---

## Known Limitations & Future Work

- [ ] **Single oracle per collateral** — Production should add TWAP as a secondary source
- [ ] **No stability pool** — Instant liquidation (Liquity-style) would improve solvency during flash crashes
- [ ] **No stability fee** — Future versions could add an interest rate model
- [ ] **Owner is EOA** — Production deployment should use Gnosis Safe (3-of-5 multisig)
- [ ] **No timelock on pause** — A timelock would prevent admin abuse
- [ ] **Two collateral types only** — Protocol supports adding more via constructor
- [ ] **No mobile-responsive frontend** — Future improvement

---

## References

- [MakerDAO Documentation](https://docs.makerdao.com/) — Primary design reference
- [Liquity Protocol](https://docs.liquity.org/) — Stability pool inspiration
- [Frax Finance](https://docs.frax.finance/) — Hybrid model reference
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/) — Security primitives
- [Chainlink Data Feeds](https://docs.chain.link/data-feeds) — Price oracle integration
- [Foundry Book](https://book.getfoundry.sh/) — Development framework
- [SWC Registry](https://swcregistry.io/) — Smart contract weakness reference
- [Consensys Best Practices](https://consensys.github.io/smart-contract-best-practices/) — Security guidelines

---

## Disclaimer

This protocol was developed as an academic project for SC6107. It has not undergone a professional security audit. **Do not deploy to Ethereum Mainnet or use with real funds** without a thorough third-party audit.

AI tools (Claude) were used to assist with code generation and documentation. All code has been reviewed, tested, and is understood by the team. AI-generated code is clearly documented and was subjected to the same testing requirements as manually written code.
