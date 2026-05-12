# Deployment Guide
## Step-by-Step Instructions — DSC Protocol

> SC6107: Blockchain Development Fundamentals (Part 2)
> DSC Protocol — Decentralized Stable Coin

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Setup](#2-repository-setup)
3. [Environment Configuration](#3-environment-configuration)
4. [Local Deployment (Anvil)](#4-local-deployment-anvil)
5. [Sepolia Testnet Deployment](#5-sepolia-testnet-deployment)
6. [Frontend Configuration & Launch](#6-frontend-configuration--launch)
7. [Post-Deployment Verification](#7-post-deployment-verification)
8. [Funding Test Accounts](#8-funding-test-accounts)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

### Required Tools

Install the following before proceeding:

#### 1.1 Foundry (Solidity development framework)

**Mac / Linux:**
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc   # or restart terminal
foundryup
```

**Windows (Git Bash):**
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

Verify installation:
```bash
forge --version    # forge 0.2.x
anvil --version    # anvil 0.2.x
cast --version     # cast 0.2.x
```

#### 1.2 Node.js (for the React frontend)

Download from https://nodejs.org — install version **18 or higher**.

Verify:
```bash
node --version    # v18.x.x or higher
npm --version     # 9.x.x or higher
```

#### 1.3 Git

Download from https://git-scm.com or install via your package manager.

```bash
git --version    # git version 2.x.x
```

#### 1.4 MetaMask Browser Extension

Install from https://metamask.io. Required for interacting with the frontend.

---

## 2. Repository Setup

### 2.1 Clone the Repository

```bash
git clone https://github.com/your-team/dsc-protocol.git
cd dsc-protocol
```

If starting from a local folder (no remote yet):
```bash
cd stablecoin-protocol
git init
git add .
git commit -m "initial commit"
```

### 2.2 Install Solidity Dependencies

Foundry uses Git submodules for dependency management. Run:

```bash
forge install OpenZeppelin/openzeppelin-contracts \
              foundry-rs/forge-std \
              smartcontractkit/chainlink
```

This creates a `lib/` directory with:
```
lib/
├── openzeppelin-contracts/   ← ERC-20, ReentrancyGuard, Pausable, Ownable
├── forge-std/                ← Test utilities (Test, console, vm)
└── chainlink/                ← AggregatorV3Interface
```

Verify the `foundry.toml` remappings are correct:
```toml
[profile.default]
src = "contracts/src"
out = "contracts/out"
libs = ["lib"]
test = "contracts/test"
```

### 2.3 Install Frontend Dependencies

```bash
cd frontend
npm install
cd ..
```

### 2.4 Compile Contracts (Verify Setup)

```bash
forge build
```

Expected output:
```
[⠒] Compiling...
[⠃] Compiling 15 files with 0.8.24
[⠊] Solc 0.8.24 finished in 3.45s
Compiler run successful!
```

If compilation fails, check the [Troubleshooting](#9-troubleshooting) section.

---

## 3. Environment Configuration

### 3.1 Create the `.env` File

```bash
cp .env.example .env
```

Open `.env` and fill in your values:

```bash
# ── Wallet ─────────────────────────────────────────────────────────────────
# Your deployer wallet private key (WITHOUT 0x prefix for some tools)
# WARNING: Never commit this file. Use a dedicated test wallet only.
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# ── RPC Endpoints ───────────────────────────────────────────────────────────
# Get a free key from https://infura.io or https://alchemy.com
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_KEY

# ── Etherscan (for contract verification) ───────────────────────────────────
# Get a free key from https://etherscan.io/myapikey
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

> **Security warning:** Never commit your `.env` file. It is listed in `.gitignore` by default. Never use a wallet that holds real mainnet funds.

### 3.2 Load Environment Variables

```bash
source .env
```

Verify the variables loaded:
```bash
echo $SEPOLIA_RPC_URL    # Should print your RPC URL
```

---

## 4. Local Deployment (Anvil)

Anvil is a local Ethereum node included with Foundry. Use this for development and testing — it runs entirely on your machine with no real funds required.

### Step 1 — Start the Local Node

Open a **new terminal window** and run:

```bash
anvil
```

Anvil will print 10 test accounts with private keys and 10,000 ETH each:

```
                             _   _
                            (_) | |
      __ _   _ __   __   __  _  | |
     / _` | | '_ \  \ \ / / | | | |
    | (_| | | | | |  \ V /  | | | |
     \__,_| |_| |_|   \_/   |_| |_|

    0.2.0 (abc1234 2024-01-01T00:00:00.000000Z)
    https://github.com/foundry-rs/foundry

Available Accounts
==================
(0) 0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266 (10000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
...

Private Keys
==================
(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
...

Listening on 127.0.0.1:8545
```

> Keep this terminal open. Anvil must be running throughout your development session.

### Step 2 — Deploy All Contracts

Open a **second terminal** in the project root and run:

```bash
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv
```

The `-vvvv` flag shows full transaction details. Expected output:

```
[⠆] Compiling...
No files changed, compilation skipped

Script ran successfully.

== Logs ==

## Setting up 1 EVM.

==========================

Chain 31337

Estimated gas price: 1 gwei
Estimated total gas used for script: 2,847,123

==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
Total Paid: 0.002847123 ETH (2847123 gas * avg 1 gwei)

Transactions saved to:
  broadcast/DeployDSC.s.sol/31337/run-latest.json
```

### Step 3 — Note the Deployed Addresses

The deployment script outputs contract addresses. Find them in the broadcast file:

```bash
cat broadcast/DeployDSC.s.sol/31337/run-latest.json | grep -E '"contractName"|"contractAddress"'
```

Example output:
```json
"contractName": "MockERC20",        "contractAddress": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
"contractName": "MockERC20",        "contractAddress": "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
"contractName": "MockV3Aggregator", "contractAddress": "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"
"contractName": "MockV3Aggregator", "contractAddress": "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9"
"contractName": "DSCoin",           "contractAddress": "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"
"contractName": "DSCEngine",        "contractAddress": "0x0165878A594ca255338adfa4d48449f69242Eb8F"
```

Record all six addresses — you will need them in Section 6.

### Step 4 — Verify Deployment On-Chain

Confirm each contract deployed correctly:

```bash
# Check DSCEngine owner (should be deployer address)
cast call 0x0165878A594ca255338adfa4d48449f69242Eb8F \
  "owner()(address)" \
  --rpc-url http://127.0.0.1:8545

# Check DSCoin owner (should be DSCEngine address — ownership was transferred)
cast call 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707 \
  "owner()(address)" \
  --rpc-url http://127.0.0.1:8545

# Check supported collateral tokens
cast call 0x0165878A594ca255338adfa4d48449f69242Eb8F \
  "getCollateralTokens()(address[])" \
  --rpc-url http://127.0.0.1:8545
```

Expected results:
- DSCEngine owner = `0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266` (Anvil account 0)
- DSCoin owner = DSCEngine address
- Collateral tokens = `[WETH_ADDRESS, WBTC_ADDRESS]`

---

## 5. Sepolia Testnet Deployment

### Step 1 — Get Sepolia ETH

You need Sepolia ETH to pay for deployment gas. Get it free from:

| Faucet | URL | Notes |
|---|---|---|
| Chainlink Faucet | https://faucets.chain.link | Requires GitHub login, most reliable |
| Alchemy Faucet | https://sepoliafaucet.com | Requires Alchemy account |
| Google Cloud | https://cloud.google.com/application/web3/faucet/ethereum/sepolia | No registration |

Request at least **0.2 ETH** to cover deployment gas costs.

### Step 2 — Configure RPC and Private Key

Ensure your `.env` has valid values:

```bash
PRIVATE_KEY=0xYOUR_DEPLOYER_PRIVATE_KEY
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
ETHERSCAN_API_KEY=YOUR_KEY

source .env
```

### Step 3 — Dry Run (Simulate Without Broadcasting)

Always simulate first to catch errors before spending gas:

```bash
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  -vvvv
```

No `--broadcast` flag means this is simulation only. Verify the output shows no errors.

### Step 4 — Deploy to Sepolia

```bash
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

The `--verify` flag automatically verifies source code on Etherscan after deployment.

Deployment takes approximately **2-5 minutes** on Sepolia. Watch for:
```
ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
```

### Step 5 — Note Sepolia Addresses

```bash
cat broadcast/DeployDSC.s.sol/11155111/run-latest.json | grep -E '"contractName"|"contractAddress"'
```

On Sepolia, only `DSCoin` and `DSCEngine` are deployed (real Chainlink feeds and WETH/WBTC are used instead of mocks).

### Step 6 — Verify on Etherscan

Visit `https://sepolia.etherscan.io/address/YOUR_DSCENGINE_ADDRESS` to confirm:
- Contract is verified (green checkmark, "Contract" tab shows source)
- Transactions are visible in the "Transactions" tab
- Read Contract functions are accessible

---

## 6. Frontend Configuration & Launch

### Step 1 — Update Contract Addresses

Open `frontend/src/hooks/useProtocol.js` and update the `ADDRESSES` object with your deployed addresses.

**For Anvil (local):**
```js
const ADDRESSES = {
  DSC_ENGINE: "0x0165878A594ca255338adfa4d48449f69242Eb8F",  // your DSCEngine
  DSC_COIN:   "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",  // your DSCoin
  WETH:       "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",  // Mock WETH
  WBTC:       "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",  // Mock WBTC
};
```

**For Sepolia:**
```js
const ADDRESSES = {
  DSC_ENGINE: "0xYOUR_DEPLOYED_DSCENGINE",
  DSC_COIN:   "0xYOUR_DEPLOYED_DSCCOIN",
  WETH:       "0xdd13E55209Fd76AfE204dBda4007C227904f0a81",  // Sepolia WETH
  WBTC:       "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",  // Sepolia WBTC
};
```

Save the file.

### Step 2 — Start the Frontend

```bash
cd frontend
npm start
```

The terminal will show:
```
Compiled successfully!
You can now view dsc-frontend in the browser.
  Local: http://localhost:3000
```

The browser opens automatically at `http://localhost:3000`.

### Step 3 — Configure MetaMask

#### Add Anvil Local Network (if using local deployment)

Open MetaMask → Networks → Add Network → Add manually:

| Field | Value |
|---|---|
| Network Name | Anvil Local |
| New RPC URL | http://127.0.0.1:8545 |
| Chain ID | 31337 |
| Currency Symbol | ETH |
| Block Explorer | (leave blank) |

Click **Save**.

#### Add Sepolia Network (if using testnet)

Sepolia is usually pre-installed in MetaMask. If not:

| Field | Value |
|---|---|
| Network Name | Sepolia Test Network |
| New RPC URL | https://rpc.sepolia.org |
| Chain ID | 11155111 |
| Currency Symbol | ETH |
| Block Explorer | https://sepolia.etherscan.io |

### Step 4 — Import a Test Wallet (Anvil Only)

For local testing, import Anvil's pre-funded account into MetaMask:

1. MetaMask → Account menu → Import Account
2. Select "Private Key"
3. Paste: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
4. Click Import

This account has 10,000 ETH on the local Anvil chain.

### Step 5 — Connect to the Frontend

1. Ensure MetaMask is on the correct network (Anvil Local or Sepolia)
2. Click **Connect Wallet** on the frontend
3. MetaMask will prompt to switch networks if needed — click **Switch**
4. MetaMask will prompt to connect — click **Connect**
5. The dashboard will load with your wallet's balances

---

## 7. Post-Deployment Verification

Run the full test suite to confirm everything works correctly:

```bash
# All tests
forge test -vvv

# With gas report
forge test --gas-report

# Coverage report
forge coverage --report lcov
```

All tests should pass:
```
Running 35 tests for contracts/test/...
[PASS] testCanDepositCollateralWithoutMinting() (gas: 68234)
[PASS] testCanMintDsc() (gas: 142819)
[PASS] testLiquidationPayoutIsCorrect() (gas: 389234)
...
Test result: ok. 35 passed; 0 failed; 0 skipped
```

### Manual On-Chain Tests (Using `cast`)

After deployment, verify the protocol works with live `cast` calls:

```bash
# Set variables
ENGINE=0x0165878A594ca255338adfa4d48449f69242Eb8F
WETH=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
WALLET=0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC=http://127.0.0.1:8545

# 1. Mint test WETH to your wallet
cast send $WETH \
  "mint(address,uint256)" $WALLET 10000000000000000000 \
  --rpc-url $RPC --private-key $PK

# 2. Check WETH balance (should be 10 WETH = 10e18)
cast call $WETH "balanceOf(address)(uint256)" $WALLET --rpc-url $RPC

# 3. Approve DSCEngine to spend WETH
cast send $WETH \
  "approve(address,uint256)" $ENGINE 10000000000000000000 \
  --rpc-url $RPC --private-key $PK

# 4. Deposit 10 WETH and mint 5000 DSC
cast send $ENGINE \
  "depositCollateralAndMintDsc(address,uint256,uint256)" \
  $WETH 10000000000000000000 5000000000000000000000 \
  --rpc-url $RPC --private-key $PK

# 5. Check health factor (should be 6e18 = 6.0)
cast call $ENGINE "getHealthFactor(address)(uint256)" $WALLET --rpc-url $RPC

# 6. Check account info
cast call $ENGINE \
  "getAccountInformation(address)(uint256,uint256)" $WALLET --rpc-url $RPC
```

---

## 8. Funding Test Accounts

### Anvil — Mint Mock Tokens

Anvil's mock tokens have an unrestricted `mint()` function for testing:

```bash
# Mint WETH
cast send $WETH \
  "mint(address,uint256)" \
  0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266 \
  1000000000000000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Mint WBTC (8 decimals — 100 WBTC = 100 × 1e8)
cast send $WBTC \
  "mint(address,uint256)" \
  0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266 \
  10000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Sepolia — Wrap ETH to WETH

On Sepolia, you need real WETH. Wrap your Sepolia ETH:

```bash
# Send ETH to the WETH contract — it auto-wraps 1:1
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 \
  --value 0.05ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

Or use the Uniswap interface at `https://app.uniswap.org` (select Sepolia network, swap ETH → WETH).

---

## 9. Troubleshooting

### `forge install` fails: "not a git repository"

```bash
# Solution: initialize git first
git init
git add .
git commit -m "initial commit"
# Then re-run forge install
```

### `forge build` fails: "file not found" or import errors

```bash
# Check remappings are correct in foundry.toml
cat foundry.toml

# Verify lib directory exists
ls lib/

# Re-install if missing
forge install OpenZeppelin/openzeppelin-contracts foundry-rs/forge-std smartcontractkit/chainlink
```

### Anvil connection refused

```bash
# Check if anvil is running
curl http://127.0.0.1:8545 -X POST \
  -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'

# If it fails, start anvil in a separate terminal
anvil
```

### MetaMask shows wrong network / WETH balance is 0

```bash
# Check which network MetaMask is connected to in browser console
const chainId = await window.ethereum.request({method: 'eth_chainId'});
console.log(chainId);
# Should be 0x7a69 (31337) for Anvil, 0xaa36a7 (11155111) for Sepolia

# Force switch to Anvil
await window.ethereum.request({
  method: 'wallet_switchEthereumChain',
  params: [{ chainId: '0x7a69' }]
});
```

### `npm start` port already in use

```bash
# Kill the existing process on port 3000
npx kill-port 3000

# Then restart
npm start
```

### Deployment reverts: "insufficient funds"

```bash
# Check deployer ETH balance
cast balance 0xf39Fd6e51aad88F6f4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545

# If on Sepolia, get more ETH from faucets listed in Section 5 Step 1
```

### Contract verification fails on Etherscan

```bash
# Manually verify after deployment
forge verify-contract \
  YOUR_CONTRACT_ADDRESS \
  contracts/src/DSCEngine.sol:DSCEngine \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address[],address[],address)" \
    "[WETH,WBTC]" "[ETH_FEED,BTC_FEED]" "DSCCOIN_ADDRESS")
```

### Health factor reads as 0 on frontend

This means the frontend is connected to a different network than where contracts are deployed. Verify:
1. MetaMask network matches deployment network
2. Contract addresses in `useProtocol.js` match the deployment
3. Anvil is still running (it resets on restart — redeploy if needed)

---

## Deployment Checklist

Use this checklist before each deployment:

```
□ foundry.toml configured correctly
□ lib/ directory populated (forge install completed)
□ frontend/node_modules/ populated (npm install completed)
□ .env file created with valid PRIVATE_KEY, RPC URLs
□ Deployer wallet has sufficient ETH for gas
□ forge build completes with no errors
□ forge test passes (35/35)

Local (Anvil):
□ anvil running in separate terminal
□ forge script deployed successfully
□ Contract addresses noted from broadcast/
□ useProtocol.js updated with Anvil addresses
□ MetaMask configured for Anvil Local (chainId 31337)
□ Anvil test account imported into MetaMask
□ Mock WETH/WBTC minted to test wallet
□ Frontend loads and shows balances

Sepolia:
□ Sepolia ETH balance > 0.1 ETH
□ SEPOLIA_RPC_URL valid and accessible
□ ETHERSCAN_API_KEY valid
□ forge script --broadcast succeeded
□ Contracts verified on Etherscan
□ useProtocol.js updated with Sepolia addresses
□ MetaMask on Sepolia network
□ Sepolia WETH obtained (faucet or wrap)
□ Frontend loads and shows balances
```

---

*Document version: 1.0 | Last updated: 2026*
*For system design details see: `docs/architecture.md`*
*For security considerations see: `docs/security-analysis.md`*
