# User Guide
## How to Interact with the DSC Protocol Application

> SC6107: Blockchain Development Fundamentals (Part 2)
> DSC Protocol — Decentralized Stable Coin

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Getting Started](#2-getting-started)
3. [Understanding the Dashboard](#3-understanding-the-dashboard)
4. [Core Actions](#4-core-actions)
   - 4.1 [Deposit Collateral & Mint DSC](#41-deposit-collateral--mint-dsc)
   - 4.2 [Redeem Collateral & Burn DSC](#42-redeem-collateral--burn-dsc)
   - 4.3 [Liquidate a Position](#43-liquidate-a-position)
5. [Managing Your Position](#5-managing-your-position)
6. [Understanding Risk](#6-understanding-risk)
7. [Frequently Asked Questions](#7-frequently-asked-questions)

---

## 1. Introduction

### What is DSC Protocol?

DSC Protocol is a decentralized stablecoin system that lets you borrow **DSC** (Decentralized Stable Coin) against your crypto assets. DSC is always worth $1 USD and is backed entirely by on-chain collateral — no banks, no companies, no trust required.

### How Does It Work?

```
You deposit WETH or WBTC
        ↓
The protocol locks your collateral
        ↓
You receive DSC tokens ($1 each)
        ↓
Use DSC anywhere, anytime
        ↓
Return DSC later to get your collateral back
```

Think of it like a crypto-backed loan: you lock up your ETH as collateral and borrow stablecoins against it. Unlike a bank loan, everything is automated by smart contracts — no application, no credit check, no waiting.

### Key Rules to Remember

| Rule | Value | What It Means |
|---|---|---|
| Collateral ratio | 150% | Need $150 of collateral to borrow $100 DSC |
| Safe zone | Health Factor ≥ 1.5 | Your position is comfortable |
| Danger zone | Health Factor < 1.2 | Consider adding collateral or repaying |
| Liquidation | Health Factor < 1.0 | Others can liquidate your position |
| Liquidation bonus | 10% | Liquidators get 10% extra — act quickly |

---

## 2. Getting Started

### What You Need

Before using the application, make sure you have:

- **MetaMask** installed in your browser (https://metamask.io)
- **A funded wallet** with WETH or WBTC (see below for how to get them)
- The application open at `http://localhost:3000`

### Step 1 — Open the Application

Navigate to `http://localhost:3000` in your browser. You will see the landing page:

```
┌─────────────────────────────────────────────────────────┐
│  🏛  Decentralized Stable Coin                          │
│                                                          │
│  Deposit WETH or WBTC as collateral and mint DSC,       │
│  a USD-pegged stablecoin.                               │
│                                                          │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐     │
│  │  150%    │  │     10%      │  │      0%       │     │
│  │Collateral│  │  Liquidation │  │   Stability   │     │
│  │  ratio   │  │    bonus     │  │     fee       │     │
│  └──────────┘  └──────────────┘  └───────────────┘     │
│                                                          │
│              [ Connect Wallet ]                          │
└─────────────────────────────────────────────────────────┘
```

### Step 2 — Connect Your Wallet

Click the **Connect Wallet** button. MetaMask will open and ask two things:

1. **Switch Network** — The app will ask to switch to the correct network (Anvil Local for testing). Click **Switch network**.

2. **Connect Account** — MetaMask will show your accounts. Select the one you want to use and click **Connect**.

Once connected, the right side of the header shows your wallet address (e.g., `0xf39F···2266`) with a green dot indicating an active connection.

### Step 3 — Get Test Tokens (Anvil Local Only)

On the local test network, you need to mint some test WETH before you can use the protocol. Run this command in Git Bash:

```bash
cast send 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
  "mint(address,uint256)" \
  YOUR_WALLET_ADDRESS \
  1000000000000000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key YOUR_PRIVATE_KEY
```

Replace `YOUR_WALLET_ADDRESS` with your MetaMask wallet address and `YOUR_PRIVATE_KEY` with the Anvil private key. After running this, you will have 1,000 WETH available.

---

## 3. Understanding the Dashboard

Once connected, the main dashboard appears. Here is a breakdown of every element:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  DSC Protocol    Sepolia Testnet              ● 0xf39F···2266           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  │
│  │  DSC Minted  │ │Collateral Val│ │Health Factor │ │  DSC Balance │  │
│  │   $5,000     │ │   $20,000    │ │     2.67     │ │    5,000     │  │
│  │     USD      │ │     USD      │ │              │ │  in wallet   │  │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  Position Health                                       6+ (safe) │  │
│  │  ████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  │
│  │  ● Healthy                                                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌────────────────────────┐  ┌────────────────────────┐               │
│  │   Ξ WETH Position      │  │   ₿ WBTC Position      │               │
│  │  Wallet    1,010 WETH  │  │  Wallet    1,000 WBTC  │               │
│  │  Deposited    10 WETH  │  │  Deposited     0 WBTC  │               │
│  └────────────────────────┘  └────────────────────────┘               │
│                                                                          │
│  ┌──────────────────┐  ┌────────────────────────────────────────────┐  │
│  │  Deposit & Mint  │  │  Deposit & Mint DSC                        │  │
│  │  Redeem & Burn   │  │                                            │  │
│  │  Liquidate       │  │  Collateral Token: [ Ξ WETH ▼ ]           │  │
│  └──────────────────┘  │  Collateral Amount: [____________]         │  │
│                         │  DSC to Mint:      [____________]         │  │
│                         │                                            │  │
│                         │           [ Deposit & Mint ]              │  │
│                         └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Header

| Element | Description |
|---|---|
| **DSC Protocol** | Application name |
| **Sepolia Testnet** | The network you are connected to |
| **● 0xf39F···2266** | Your connected wallet address. Green dot = connected |

### Stats Cards (Top Row)

| Card | Description |
|---|---|
| **DSC Minted** | Total USD value of DSC you have borrowed from the protocol |
| **Collateral Value** | Total USD value of all your deposited collateral (live price) |
| **Health Factor** | Your position safety score (see Section 6 for full explanation) |
| **DSC Balance** | How many DSC tokens you currently hold in your wallet |

> Note: DSC Minted and DSC Balance may differ. If you transfer or spend your DSC, your balance drops but your debt (DSC Minted) remains until you burn DSC to repay it.

### Position Health Bar

A visual representation of your health factor:

| Bar Color | Health Factor | Status |
|---|---|---|
| 🟢 Green (full) | ∞ (no debt) | No position open |
| 🟢 Green | ≥ 2.0 | Comfortably safe |
| 🟡 Yellow | 1.2 – 2.0 | Moderate risk |
| 🔴 Red | < 1.0 | LIQUIDATABLE |

The label beneath the bar shows:
- **"No debt — infinitely safe"** — no DSC minted yet
- **"Healthy"** — health factor comfortably above 1.0
- **"Risky"** — health factor approaching 1.0
- **"LIQUIDATABLE"** — health factor below 1.0, position can be liquidated

### Collateral Position Cards

Two cards show your position for each supported collateral type:

| Row | Description |
|---|---|
| **Wallet** | How many tokens you hold in your MetaMask wallet (available to deposit) |
| **Deposited** | How many tokens are currently locked in the protocol as collateral |

### Action Panel (Left Navigation)

Three sections accessible from the left menu:
- **Deposit & Mint** — Open or increase a position
- **Redeem & Burn** — Close or reduce a position
- **Liquidate** — Liquidate another user's unhealthy position

---

## 4. Core Actions

### 4.1 Deposit Collateral & Mint DSC

Use this to open a new position or add to an existing one. You deposit crypto collateral and receive DSC stablecoins in return.

#### When to Use
- You want to access liquidity without selling your crypto
- You want to increase the amount of DSC you hold
- You want to add more collateral to improve your health factor

#### Step-by-Step

**1.** Click **Deposit & Mint** in the left navigation panel.

**2.** Select your collateral token from the dropdown:
   - **Ξ WETH** — Wrapped Ether (18 decimals)
   - **₿ WBTC** — Wrapped Bitcoin (8 decimals)

**3.** Enter the **Collateral Amount** — how much of the token you want to deposit.

```
Example: Collateral Amount = 10
         (deposits 10 WETH worth $20,000 at $2,000/ETH)
```

**4.** Enter the **DSC to Mint** — how many DSC tokens you want to receive.

```
Example: DSC to Mint = 5000
         (borrows $5,000 worth of DSC)
         
Resulting Health Factor = ($20,000 × 1.5) / $5,000 = 6.0  ✅
```

> **Safe minting guideline:** To stay safe, mint no more than **50%** of your maximum. With $20,000 collateral, maximum is $13,333 DSC — so aim for $6,666 or less. This gives you a health factor of 4.5+, providing a large buffer against price drops.

**5.** Click **Deposit & Mint**.

**6.** MetaMask will show **two transaction confirmations**:

   - **Transaction 1 — Approve:** Allows the DSCEngine contract to spend your WETH. Click **Confirm**.
   - **Transaction 2 — Deposit & Mint:** The actual deposit and minting transaction. Click **Confirm**.

**7.** Wait for both transactions to confirm (approximately 15 seconds each on local Anvil, 15–30 seconds on Sepolia).

**8.** The dashboard automatically refreshes. You will see:
   - **DSC Minted** increased by your minted amount
   - **Collateral Value** increased by your deposited amount
   - **Health Factor** updated to reflect your new position
   - **Position Health** bar updated with new color
   - **WETH Deposited** increased, **WETH Wallet** decreased
   - **DSC Balance** increased by your minted amount
   - Green success banner: `Success! Tx: 0x4f6fb208...`

#### What Happens On-Chain

```
1. Your WETH is transferred from your wallet → DSCEngine contract
2. DSCEngine records: s_collateralDeposited[you][WETH] += amount
3. DSCEngine checks: healthFactor(you) >= 1.0
4. DSCEngine calls: DSCoin.mint(you, dscAmount)
5. DSC tokens appear in your wallet
```

---

### 4.2 Redeem Collateral & Burn DSC

Use this to close or reduce your position. You return DSC to the protocol and receive your collateral back.

#### When to Use
- You want to retrieve your deposited collateral
- Your health factor is dropping and you want to repay debt to improve it
- You no longer need the DSC and want to exit the position

#### Step-by-Step

**1.** Click **Redeem & Burn** in the left navigation panel.

**2.** Select the collateral token you want to retrieve (**WETH** or **WBTC**).

**3.** Enter the **Collateral to Redeem** — how much collateral you want to withdraw.

**4.** Enter the **DSC to Burn** — how much DSC debt you want to repay.

```
Example: You have 10 WETH deposited, $5,000 DSC minted
         Redeem: 5 WETH
         Burn:   2,500 DSC
         
After operation:
  Collateral = 5 WETH ($10,000)
  Debt       = $2,500 DSC
  New HF     = ($10,000 × 1.5) / $2,500 = 6.0  ✅
```

> **Important:** The protocol checks your health factor after the operation. If redeeming that much collateral or burning that little DSC would leave your health factor below 1.0, the transaction will revert. Make sure your remaining position stays healthy.

**5.** Click **Redeem & Burn**.

**6.** MetaMask shows **two transaction confirmations**:
   - **Transaction 1 — Approve DSC:** Allows DSCEngine to spend your DSC for burning.
   - **Transaction 2 — Redeem & Burn:** The actual redemption.

**7.** After confirmation, the dashboard updates:
   - **DSC Minted** decreased
   - **Collateral Value** decreased
   - **WETH Wallet** balance increased (collateral returned)
   - **WETH Deposited** decreased
   - **DSC Balance** decreased

#### Fully Closing a Position

To completely exit: burn all your DSC and redeem all your collateral.

```
DSC to Burn    = your entire DSC Minted amount
Collateral     = your entire deposited amount
```

After a full close, your health factor returns to ∞ and the position health bar shows "No debt — infinitely safe."

---

### 4.3 Liquidate a Position

Use this to liquidate another user's position when their health factor has dropped below 1.0. You repay some of their DSC debt and receive their collateral at a 10% discount.

#### When to Use
- You find a position with health factor < 1.0
- You hold enough DSC to cover part or all of their debt
- You want to profit from the 10% liquidation bonus

#### Prerequisites

Before liquidating, you need:
1. **DSC tokens** in your wallet (at least the amount you plan to cover)
2. The **target user's wallet address**
3. Confirmation their health factor is below 1.0

#### Step-by-Step

**1.** Click **Liquidate** in the left navigation panel.

**2.** Select the **Collateral Token to Seize** — which of the user's collateral you want to receive.

**3.** Enter the **User Address** — the wallet address of the undercollateralized position.

```
Example: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
```

**4.** Enter the **DSC Debt to Cover** — how much of their debt you will repay.

```
Example scenario:
  Target user: 10 WETH deposited, $13,000 DSC minted
  ETH price crashed to $800/ETH
  Their HF = ($8,000 × 1.5) / $13,000 = 0.92  ❌ LIQUIDATABLE
  
  You enter: DSC to Cover = 5000
  
  You will receive:
    Base: $5,000 / $800 = 6.25 WETH
    Bonus (10%): +0.625 WETH
    Total: 6.875 WETH worth $5,500 at $800/ETH
    
  Your profit: $500 (10% of $5,000)
```

**5.** Click **Liquidate**.

**6.** MetaMask shows two confirmations:
   - **Transaction 1 — Approve DSC:** Approve DSCEngine to spend your DSC.
   - **Transaction 2 — Liquidate:** Execute the liquidation.

**7.** After confirmation:
   - Your **WETH Wallet** increases (seized collateral + bonus)
   - Your **DSC Balance** decreases (DSC you paid)
   - The target user's debt and collateral are reduced

#### Liquidation Rules

- You **cannot** liquidate a healthy position (HF ≥ 1.0). The transaction reverts.
- Partial liquidation is allowed — you do not need to cover the entire debt.
- Your own position must remain healthy after liquidating (your HF is checked too).
- The liquidation must improve the target user's health factor — you cannot over-liquidate.

---

## 5. Managing Your Position

### Monitoring Your Health Factor

Your health factor changes every time the ETH or BTC price moves. Check it regularly:

| Health Factor | Action Recommended |
|---|---|
| > 3.0 | Position is very safe, no action needed |
| 2.0 – 3.0 | Comfortable, monitor occasionally |
| 1.5 – 2.0 | Starting to tighten, keep an eye on prices |
| 1.2 – 1.5 | Consider adding collateral or burning some DSC |
| 1.0 – 1.2 | Act immediately — you are close to liquidation |
| < 1.0 | You are liquidatable — act immediately |

### How to Improve Your Health Factor

You have two options to improve a falling health factor:

**Option A — Add More Collateral**

Deposit additional WETH or WBTC without minting more DSC:
1. Go to **Deposit & Mint**
2. Enter the additional collateral amount
3. Set **DSC to Mint = 0** (or a very small amount)
4. Click Deposit & Mint

This increases your collateral value, which directly improves your health factor.

**Option B — Burn Some DSC**

Repay part of your DSC debt:
1. Go to **Redeem & Burn**
2. Set **Collateral to Redeem = 0** (redeem nothing)
3. Enter the **DSC to Burn** amount
4. Click Redeem & Burn

This reduces your debt, which directly improves your health factor.

### Health Factor Examples

```
Starting position: 10 WETH @ $2,000, 5,000 DSC minted
HF = ($20,000 × 1.5) / $5,000 = 6.0

ETH price drops to $1,000:
HF = ($10,000 × 1.5) / $5,000 = 3.0  (still safe)

ETH price drops to $500:
HF = ($5,000 × 1.5) / $5,000 = 1.5  (getting close)

ETH price drops to $400:
HF = ($4,000 × 1.5) / $5,000 = 1.2  (act now)

ETH price drops to $333:
HF = ($3,330 × 1.5) / $5,000 = 0.99  (LIQUIDATABLE)
```

To stay safe with 10 WETH, you should keep minted DSC well below the maximum:

| ETH Price | Max Safe DSC | Recommended DSC |
|---|---|---|
| $2,000 | $13,333 | $6,666 (HF = 4.5) |
| $1,500 | $10,000 | $5,000 (HF = 4.5) |
| $1,000 | $6,666 | $3,333 (HF = 4.5) |

---

## 6. Understanding Risk

### Price Risk

Your health factor depends on the live market price of your collateral. If ETH or BTC prices fall significantly, your health factor decreases. You can be liquidated even while you sleep — crypto markets operate 24/7.

**How to reduce price risk:**
- Keep your health factor well above 1.5 (ideally above 3.0)
- Mint only 40–50% of your maximum allowed DSC
- Monitor prices regularly and act if markets are volatile

### Liquidation Risk

If your health factor falls below 1.0, anyone can liquidate your position. The liquidator:
- Repays some or all of your DSC debt
- Receives your collateral at a 10% discount

This means you lose more collateral than your debt is worth. For example:

```
You owe: $5,000 DSC
Liquidator pays: $5,000 DSC
Liquidator receives: $5,500 worth of your WETH (10% bonus)

Your loss: extra $500 of collateral seized
```

The best protection against liquidation is maintaining a high health factor.

### Smart Contract Risk

All funds are held in smart contracts. While the contracts have been tested and reviewed, smart contract bugs are always possible. This is a student project — do not use real funds.

---

## 7. Frequently Asked Questions

**Q: What is DSC pegged to?**
A: 1 DSC = $1 USD. The peg is maintained by over-collateralization and liquidations, not by holding real US dollars.

**Q: Is there an interest rate on my borrowed DSC?**
A: No. The current version charges 0% stability fee. You can hold your DSC position indefinitely at no cost (other than the opportunity cost of locked collateral).

**Q: Can I lose more than I deposit?**
A: No. Your maximum loss is your deposited collateral. The protocol cannot take more than what you have deposited.

**Q: What happens if the Chainlink oracle goes offline?**
A: The protocol pauses itself automatically if the price feed is more than 3 hours old. No new deposits, mints, or liquidations can happen until the oracle recovers.

**Q: Can I use WBTC and WETH at the same time?**
A: Yes. Your health factor considers all your collateral across all supported tokens combined.

**Q: What is the minimum amount I can deposit or mint?**
A: Any amount greater than zero. However, very small amounts may not be worth the gas cost.

**Q: How do I know if a position is liquidatable?**
A: Check the health factor of the address using the protocol's read functions. Any address with health factor < 1.0 is liquidatable.

**Q: If I transfer my DSC to someone else, do I still owe the debt?**
A: Yes. Your debt is tracked by your wallet address in the protocol. Transferring DSC to another wallet does not reduce your recorded debt — you still need to return DSC to the protocol (from any source) to close your position.

**Q: What does the "Success! Tx: 0x..." message mean?**
A: It confirms your transaction was included in a block on the blockchain. The hex string is the transaction hash — you can search for it on Etherscan (Sepolia) or a block explorer to see full details.

**Q: Why does the dashboard show "LIQUIDATABLE" even with no position?**
A: When DSC minted = 0, the health factor calculation returns 0 (division by zero). This is a display issue — without any minted DSC you have no liquidatable position. Once you mint DSC and have collateral, the health factor displays correctly.

---

*Document version: 1.0 | Last updated: 2026*
*For deployment instructions see: `docs/deployment-guide.md`*
*For technical details see: `docs/architecture.md`*
