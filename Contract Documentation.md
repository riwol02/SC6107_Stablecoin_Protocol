# Contract Documentation
## NatSpec Comments — All Public & External Functions

> SC6107: Blockchain Development Fundamentals (Part 2)
> DSC Protocol — Decentralized Stable Coin
> Solidity Version: 0.8.24 | Framework: Foundry | Library: OpenZeppelin 5.x

---

## Table of Contents

1. [DSCoin.sol](#1-dscoinsol)
2. [DSCEngine.sol](#2-dscenginesol)
3. [OracleLib.sol](#3-oraclelibsol)
4. [NatSpec Quick Reference](#4-natspec-quick-reference)

---

## 1. DSCoin.sol

**Contract path:** `contracts/src/DSCoin.sol`
**Inherits:** `ERC20Burnable`, `Ownable`
**Purpose:** The ERC-20 stablecoin token. Minting and burning are restricted to the `DSCEngine` contract (owner). All standard ERC-20 functions (transfer, approve, etc.) are inherited from OpenZeppelin and fully available to token holders.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DSCoin (Decentralized Stable Coin)
/// @author SC6107 Team
/// @notice An ERC-20 stablecoin pegged 1:1 to USD, backed by exogenous
///         crypto collateral (WETH, WBTC).
/// @dev    Minting and burning are controlled exclusively by the DSCEngine
///         contract (the owner). This contract is intentionally minimal —
///         all collateral logic and peg maintenance live in DSCEngine.
///
///         Stability mechanism : Algorithmic (governed by DSCEngine)
///         Collateral          : Exogenous (WETH, WBTC)
///         Peg                 : USD (via Chainlink price feeds in DSCEngine)
contract DSCoin is ERC20Burnable, Ownable {
```

---

### 1.1 Constructor

```solidity
/// @notice Deploys the DSCoin token and assigns ownership to the deployer.
/// @dev    Ownership MUST be transferred to the DSCEngine contract immediately
///         after deployment via transferOwnership(dscEngineAddress).
///         Until that transfer, the deployer holds minting/burning rights.
constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable(msg.sender)
```

---

### 1.2 `mint`

```solidity
/// @notice Mints new DSC tokens to the specified address.
/// @dev    Only callable by the owner (DSCEngine). Enforces two invariants:
///         1. Cannot mint to the zero address (would permanently lock tokens).
///         2. Amount must be greater than zero (prevents no-op transactions).
///         This function is the sole mechanism for increasing DSC supply.
///         Supply growth is therefore always backed by new collateral deposits.
/// @param  to     The address that receives the newly minted DSC tokens.
///                Must not be address(0).
/// @param  amount The number of DSC tokens to mint, denominated in wei (1e18 = 1 DSC).
///                Must be greater than zero.
/// @return        Always returns true on success; reverts on any failure.
/// @custom:throws DSCoin__NotZeroAddress    if `to` is the zero address.
/// @custom:throws DSCoin__MustBeMoreThanZero if `amount` is zero.
/// @custom:throws OwnableUnauthorizedAccount if caller is not the owner.
function mint(address to, uint256 amount) external onlyOwner returns (bool)
```

---

### 1.3 `burn`

```solidity
/// @notice Burns DSC tokens from the caller's (owner's) balance.
/// @dev    Overrides ERC20Burnable.burn() to add onlyOwner restriction and
///         explicit balance check with a descriptive custom error.
///         Called by DSCEngine when a user repays their DSC debt or when
///         a liquidator covers a position. Tokens must first be transferred
///         to DSCEngine before this function is called.
/// @param  amount The number of DSC tokens to burn, denominated in wei.
///                Must be greater than zero and ≤ the owner's current balance.
/// @custom:throws DSCoin__MustBeMoreThanZero  if `amount` is zero.
/// @custom:throws DSCoin__BurnAmountExceedsBalance if amount > balanceOf(owner).
/// @custom:throws OwnableUnauthorizedAccount  if caller is not the owner.
function burn(uint256 amount) public override onlyOwner
```

---

### 1.4 Inherited ERC-20 Functions (from OpenZeppelin)

These functions are inherited unchanged from `ERC20` and `ERC20Burnable`. They are available to all token holders without restriction.

| Function | Visibility | Description |
|---|---|---|
| `transfer(address to, uint256 amount)` | `public` | Transfer DSC tokens to another address |
| `transferFrom(address from, address to, uint256 amount)` | `public` | Transfer tokens using allowance |
| `approve(address spender, uint256 amount)` | `public` | Approve spender to use tokens |
| `allowance(address owner, address spender)` | `public view` | Query current allowance |
| `balanceOf(address account)` | `public view` | Query token balance |
| `totalSupply()` | `public view` | Query total DSC in circulation |
| `name()` | `public view` | Returns "Decentralized Stable Coin" |
| `symbol()` | `public view` | Returns "DSC" |
| `decimals()` | `public view` | Returns 18 |
| `burnFrom(address account, uint256 amount)` | `public` | Burn from another address using allowance |

---

## 2. DSCEngine.sol

**Contract path:** `contracts/src/DSCEngine.sol`
**Inherits:** `ReentrancyGuard`, `Pausable`, `Ownable`
**Purpose:** Core protocol engine. Manages all collateral deposits, DSC minting, redemptions, and liquidations. Enforces the health factor invariant on every state-changing operation.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  DSCEngine — Core Engine for the Decentralized Stable Coin Protocol
/// @author SC6107 Team
/// @notice Manages collateral deposits, DSC minting/burning, and liquidations.
///
/// @dev    Key invariant: the protocol must always be over-collateralized.
///         At all times: total collateral value (USD) > total DSC supply (USD).
///
///         Collateralization ratio : 150%  ($150 collateral → max $100 DSC)
///         Liquidation threshold   : 150%  (health factor < 1 → liquidatable)
///         Liquidation bonus       : 10%   (incentive for liquidators)
///
///         Supported collateral : WETH, WBTC (configurable at deploy time)
///         Price feeds          : Chainlink (stale-price protected via OracleLib)
///
///         Security considerations:
///           - ReentrancyGuard on all state-changing external functions
///           - Checks-Effects-Interactions pattern throughout
///           - Emergency pause via Pausable (owner only)
///           - Chainlink stale price check (3-hour timeout)
///           - No unchecked arithmetic (Solidity 0.8.x built-in protection)
contract DSCEngine is ReentrancyGuard, Pausable, Ownable {
```

---

### 2.1 Constructor

```solidity
/// @notice Deploys the DSCEngine and configures all supported collateral tokens.
/// @dev    Iterates over `tokenAddresses` and maps each to its corresponding
///         Chainlink price feed. Also stores them in `s_collateralTokens` for
///         iteration in getAccountCollateralValue().
///         Reverts if array lengths don't match to prevent silent misconfiguration.
/// @param  tokenAddresses     Ordered array of ERC-20 collateral token addresses
///                            (e.g., [WETH_ADDRESS, WBTC_ADDRESS]).
/// @param  priceFeedAddresses Chainlink AggregatorV3Interface addresses corresponding
///                            to each token in tokenAddresses
///                            (e.g., [ETH_USD_FEED, BTC_USD_FEED]).
/// @param  dscAddress         Address of the deployed DSCoin contract. Ownership
///                            of DSCoin must be transferred to this contract after
///                            deployment.
/// @custom:throws DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
///                if tokenAddresses.length != priceFeedAddresses.length.
constructor(
    address[] memory tokenAddresses,
    address[] memory priceFeedAddresses,
    address dscAddress
) Ownable(msg.sender)
```

---

### 2.2 `depositCollateralAndMintDsc`

```solidity
/// @notice Deposits collateral and mints DSC in a single atomic transaction.
/// @dev    Convenience wrapper that calls depositCollateral() then mintDsc()
///         in sequence. Both operations are subject to the health factor check
///         enforced inside mintDsc(). If health factor would break, the entire
///         transaction reverts — no partial state changes occur.
///         Emits CollateralDeposited and DSCMinted events on success.
/// @param  tokenCollateralAddress The ERC-20 token address to use as collateral.
///                                Must be in the allowed tokens list.
/// @param  amountCollateral       Amount of collateral tokens to deposit,
///                                in the token's native decimals (e.g., 1e18 for 1 WETH).
///                                Must be greater than zero.
/// @param  amountDscToMint        Amount of DSC to mint, in wei (1e18 = 1 DSC).
///                                Must result in health factor >= 1.0 after minting.
/// @custom:throws DSCEngine__NeedsMoreThanZero   if either amount is zero.
/// @custom:throws DSCEngine__TokenNotAllowed      if token is not whitelisted.
/// @custom:throws DSCEngine__BreaksHealthFactor   if mint would drop HF below 1.0.
/// @custom:throws DSCEngine__MintFailed           if DSCoin.mint() returns false.
/// @custom:throws EnforcedPause                   if protocol is paused.
function depositCollateralAndMintDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToMint
) external whenNotPaused
```

---

### 2.3 `depositCollateral`

```solidity
/// @notice Deposits ERC-20 collateral tokens into the protocol.
/// @dev    Follows strict Checks-Effects-Interactions ordering:
///         1. CHECK  — validate token and amount
///         2. EFFECT — update s_collateralDeposited mapping
///         3. INTERACT — transfer tokens from caller to this contract
///         The nonReentrant modifier protects against reentrancy from malicious
///         ERC-20 tokens. SafeERC20 ensures the transfer reverts on failure
///         (handles non-standard tokens that return false instead of reverting).
///         The caller must have approved this contract to spend `amountCollateral`
///         tokens before calling this function.
/// @param  tokenCollateralAddress The ERC-20 token address to deposit.
///                                Must be in the allowed collateral token list
///                                (configured at deployment).
/// @param  amountCollateral       Amount of tokens to deposit, in the token's
///                                native decimals. Must be greater than zero.
/// @custom:throws DSCEngine__NeedsMoreThanZero  if amountCollateral is zero.
/// @custom:throws DSCEngine__TokenNotAllowed    if token has no registered price feed.
/// @custom:throws EnforcedPause                 if protocol is paused.
/// @custom:emits  CollateralDeposited(user, token, amount) on success.
function depositCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) public whenNotPaused moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant
```

---

### 2.4 `mintDsc`

```solidity
/// @notice Mints DSC tokens against the caller's deposited collateral.
/// @dev    Updates s_DSCMinted before calling the health factor check to
///         ensure the check reflects the post-mint state (conservative approach).
///         The health factor check is performed BEFORE calling DSCoin.mint(),
///         following the Checks-Effects-Interactions pattern.
///         Includes a circuit breaker: reverts if amountDscToMint > MAX_MINT_PER_TX
///         (1,000,000 DSC) to limit single-transaction exposure.
///         Caller must have previously deposited sufficient collateral such that:
///         health_factor = (collateral_usd × 1.5) / (existing_dsc + amountDscToMint) >= 1.0
/// @param  amountDscToMint  The number of DSC tokens to mint, in wei (1e18 = 1 DSC).
///                          Must be > 0 and ≤ MAX_MINT_PER_TX (1,000,000e18).
///                          Must not cause the caller's health factor to drop below 1.0.
/// @custom:throws DSCEngine__NeedsMoreThanZero  if amountDscToMint is zero.
/// @custom:throws DSCEngine__BreaksHealthFactor  if resulting HF < MIN_HEALTH_FACTOR.
/// @custom:throws DSCEngine__MintFailed          if DSCoin.mint() returns false.
/// @custom:throws EnforcedPause                  if protocol is paused.
/// @custom:emits  DSCMinted(user, amount) on success.
function mintDsc(
    uint256 amountDscToMint
) public whenNotPaused moreThanZero(amountDscToMint) nonReentrant
```

---

### 2.5 `redeemCollateralForDsc`

```solidity
/// @notice Burns DSC tokens and redeems collateral in a single atomic transaction.
/// @dev    Convenience wrapper: burns DSC first (reducing debt), then redeems
///         collateral. Health factor is checked after both operations to ensure
///         the position remains valid. The order (burn first, then redeem) is
///         intentionally chosen to minimize the window where health factor
///         could be temporarily violated.
///         Caller must have approved DSCEngine to spend `amountDscToBurn` DSC
///         tokens before calling this function.
/// @param  tokenCollateralAddress  The collateral token to withdraw.
///                                 Must be in the allowed tokens list.
/// @param  amountCollateral        Amount of collateral tokens to retrieve,
///                                 in the token's native decimals. Must be > 0.
/// @param  amountDscToBurn         Amount of DSC to burn, in wei.
///                                 Will reduce the caller's recorded debt.
/// @custom:throws DSCEngine__NeedsMoreThanZero  if amountCollateral is zero.
/// @custom:throws DSCEngine__TokenNotAllowed    if token is not whitelisted.
/// @custom:throws DSCEngine__BreaksHealthFactor if remaining HF < 1.0 after operations.
/// @custom:throws EnforcedPause                 if protocol is paused.
function redeemCollateralForDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToBurn
) external whenNotPaused moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress)
```

---

### 2.6 `redeemCollateral`

```solidity
/// @notice Withdraws deposited collateral without burning DSC.
/// @dev    Reduces the caller's collateral balance and transfers tokens back.
///         Health factor is verified after redemption — if the withdrawal
///         would make the position undercollateralized, the transaction reverts.
///         This prevents users from accidentally (or maliciously) withdrawing
///         so much collateral that their remaining position becomes liquidatable.
///         Follows Checks-Effects-Interactions: storage updated before transfer.
/// @param  tokenCollateralAddress  The collateral token to withdraw.
///                                 Must be in the allowed tokens list.
/// @param  amountCollateral        Amount of collateral to withdraw, in the
///                                 token's native decimals. Must be > 0 and
///                                 ≤ the caller's deposited balance.
/// @custom:throws DSCEngine__NeedsMoreThanZero  if amountCollateral is zero.
/// @custom:throws DSCEngine__TokenNotAllowed    if token is not whitelisted.
/// @custom:throws DSCEngine__BreaksHealthFactor if HF < 1.0 after withdrawal.
/// @custom:throws EnforcedPause                 if protocol is paused.
/// @custom:emits  CollateralRedeemed(from, to, token, amount) on success.
function redeemCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) external whenNotPaused moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant
```

---

### 2.7 `burnDsc`

```solidity
/// @notice Burns DSC tokens to reduce the caller's outstanding debt.
/// @dev    Transfers DSC from the caller to this contract, then burns them.
///         The caller must have approved DSCEngine to spend `amount` DSC tokens.
///         Reduces s_DSCMinted[caller] by `amount`, which improves the health factor.
///         Health factor check after burning should never fail (burning only
///         improves HF), but is included as a safety assertion.
///         Use redeemCollateralForDsc() to burn and retrieve collateral in one step.
/// @param  amount  The number of DSC tokens to burn, in wei (1e18 = 1 DSC).
///                 Must be greater than zero and ≤ the caller's minted DSC balance
///                 as tracked in s_DSCMinted (not the ERC-20 balance).
/// @custom:throws DSCEngine__NeedsMoreThanZero  if amount is zero.
/// @custom:throws EnforcedPause                 if protocol is paused.
/// @custom:emits  DSCBurned(user, amount) on success.
function burnDsc(uint256 amount) external whenNotPaused moreThanZero(amount)
```

---

### 2.8 `liquidate`

```solidity
/// @notice Liquidates an undercollateralized position by repaying debt on behalf
///         of the position owner and seizing their collateral at a 10% bonus.
/// @dev    This is the primary mechanism that maintains protocol solvency.
///         Liquidation is permissionless — any address may act as liquidator.
///         The function enforces three critical conditions:
///         1. The target user's health factor must be < MIN_HEALTH_FACTOR (1.0)
///            before liquidation. If the position is healthy, it cannot be touched.
///         2. Seized collateral = debtToCover_in_tokens × 1.10 (10% bonus)
///            This bonus incentivizes liquidators to act quickly.
///         3. The target user's health factor must IMPROVE after liquidation.
///            This prevents liquidators from seizing more collateral than necessary
///            and prevents abuse of the liquidation system.
///         The liquidator must:
///           a) Hold at least `debtToCover` DSC tokens.
///           b) Have approved DSCEngine to spend `debtToCover` DSC before calling.
///         Partial liquidations are supported — `debtToCover` can be less than
///         the user's total debt.
/// @param  collateral    The ERC-20 collateral token to seize from the user.
///                       Must be in the allowed tokens list.
/// @param  user          The address of the undercollateralized position to liquidate.
///                       Must have health factor < 1.0 (MIN_HEALTH_FACTOR).
/// @param  debtToCover   Amount of DSC debt to repay on behalf of `user`, in wei.
///                       Determines how much collateral the liquidator receives.
///                       Must be greater than zero.
/// @custom:throws DSCEngine__NeedsMoreThanZero   if debtToCover is zero.
/// @custom:throws DSCEngine__HealthFactorOk      if user's HF >= MIN_HEALTH_FACTOR.
/// @custom:throws DSCEngine__HealthFactorNotImproved if user's HF didn't improve.
/// @custom:throws DSCEngine__BreaksHealthFactor  if liquidator's own HF breaks.
/// @custom:throws EnforcedPause                  if protocol is paused.
/// @custom:emits  Liquidated(liquidator, user, collateral, debtCovered, collateralSeized)
function liquidate(
    address collateral,
    address user,
    uint256 debtToCover
) external whenNotPaused moreThanZero(debtToCover) nonReentrant
```

---

### 2.9 `pause`

```solidity
/// @notice Pauses all state-changing protocol operations in case of emergency.
/// @dev    When paused, the following functions revert with EnforcedPause:
///         depositCollateral, mintDsc, depositCollateralAndMintDsc,
///         redeemCollateral, redeemCollateralForDsc, burnDsc, liquidate.
///         Read-only functions (getHealthFactor, getUsdValue, etc.) remain
///         available while paused.
///         In production, the owner should be a Gnosis Safe multisig (3-of-5)
///         with a timelock to prevent unilateral admin action.
///         Emits ProtocolPaused event on success.
/// @custom:throws OwnableUnauthorizedAccount if caller is not the owner.
/// @custom:throws EnforcedPause              if protocol is already paused.
function pause() external onlyOwner
```

---

### 2.10 `unpause`

```solidity
/// @notice Resumes all protocol operations after an emergency pause.
/// @dev    Re-enables all state-changing functions that were blocked by pause().
///         Should only be called after the security incident that triggered
///         the pause has been fully investigated and resolved.
///         Emits ProtocolUnpaused event on success.
/// @custom:throws OwnableUnauthorizedAccount if caller is not the owner.
/// @custom:throws ExpectedPause              if protocol is not currently paused.
function unpause() external onlyOwner
```

---

### 2.11 `getUsdValue`

```solidity
/// @notice Returns the USD value of a given amount of a collateral token.
/// @dev    Fetches the latest price from the Chainlink feed registered for
///         `token` via OracleLib.staleCheckLatestRoundData(), which will revert
///         if the price is older than 3 hours.
///         Price feed returns 8-decimal prices; amount is assumed 18 decimals.
///         Result formula: (price × ADDITIONAL_FEED_PRECISION × amount) / PRECISION
///         where ADDITIONAL_FEED_PRECISION = 1e10 (converts 8→18 decimals)
///         and PRECISION = 1e18.
///         Example: 1 ETH at $2,000:
///           price = 2000e8, amount = 1e18
///           result = (2000e8 × 1e10 × 1e18) / 1e18 = 2000e18 ($2,000)
/// @param  token   The ERC-20 collateral token address. Must be whitelisted.
/// @param  amount  The quantity of tokens to value, in the token's native decimals
///                 (assumed 18 decimals; WBTC users should note this).
/// @return         The USD value scaled to 18 decimals (1e18 = $1.00).
/// @custom:throws OracleLib__StalePrice if the Chainlink feed hasn't updated in 3h.
function getUsdValue(address token, uint256 amount) public view returns (uint256)
```

---

### 2.12 `getTokenAmountFromUsd`

```solidity
/// @notice Returns the token amount equivalent to a given USD value.
/// @dev    Inverse of getUsdValue(). Used during liquidation to calculate
///         how many collateral tokens to seize for a given DSC debt amount.
///         Formula: (usdAmountInWei × PRECISION) / (price × ADDITIONAL_FEED_PRECISION)
///         Example: $1,000 worth of ETH at $2,000/ETH:
///           result = (1000e18 × 1e18) / (2000e8 × 1e10) = 0.5e18 (0.5 ETH)
///         Note: Integer division may cause 1-wei rounding errors; this is
///         acceptable for protocol purposes and is tested in fuzz tests.
/// @param  token             The collateral token address. Must be whitelisted.
/// @param  usdAmountInWei    The USD value to convert, scaled to 18 decimals
///                           (e.g., $100 = 100e18).
/// @return                   The equivalent token amount in 18 decimal precision.
/// @custom:throws OracleLib__StalePrice if Chainlink feed is stale.
function getTokenAmountFromUsd(
    address token,
    uint256 usdAmountInWei
) public view returns (uint256)
```

---

### 2.13 `getAccountCollateralValue`

```solidity
/// @notice Returns the total USD value of all collateral deposited by a user.
/// @dev    Iterates over all supported collateral tokens in s_collateralTokens[],
///         reads the user's balance for each, and sums their USD values via
///         getUsdValue(). If any price feed is stale, the entire call reverts.
///         Gas note: the loop is bounded by the number of supported collateral
///         tokens (currently 2), making the gas cost predictable and low.
/// @param  user  The address to query. Can be any address (not just msg.sender).
/// @return totalCollateralValueInUsd  The sum of all collateral USD values,
///                                    scaled to 18 decimals.
function getAccountCollateralValue(address user)
    public view
    returns (uint256 totalCollateralValueInUsd)
```

---

### 2.14 `getAccountInformation`

```solidity
/// @notice Returns the DSC debt and collateral value for a user in one call.
/// @dev    Combines s_DSCMinted lookup and getAccountCollateralValue() into
///         a single external call. Useful for frontend dashboards and off-chain
///         monitoring tools that need both values simultaneously.
///         The returned values can be passed directly to calculateHealthFactor()
///         to determine the user's current health factor without an extra call.
/// @param  user  The address to query.
/// @return totalDscMinted       Amount of DSC the user has minted, in wei.
///                              Represents their outstanding debt to the protocol.
/// @return collateralValueInUsd Total USD value of all collateral deposited,
///                              scaled to 18 decimals.
function getAccountInformation(address user)
    external view
    returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
```

---

### 2.15 `getHealthFactor`

```solidity
/// @notice Returns the current health factor for a given user.
/// @dev    Health factor is defined as:
///           HF = (collateral_value_usd × LIQUIDATION_THRESHOLD / 100) × 1e18
///                / total_dsc_minted
///         A health factor ≥ 1e18 (≥ 1.0) indicates a healthy position.
///         A health factor < 1e18 (< 1.0) indicates the position is liquidatable.
///         Special case: if total_dsc_minted == 0, returns type(uint256).max
///         representing an infinitely safe position (no debt).
///         This function reads live Chainlink prices — results may vary between
///         blocks if price feeds are updating.
/// @param  user  The address to check. Can be any address.
/// @return       Health factor scaled to 1e18.
///               Examples: 6e18 = HF of 6.0, 1e18 = HF of 1.0 (liquidation threshold),
///               type(uint256).max = infinite (no debt).
function getHealthFactor(address user) external view returns (uint256)
```

---

### 2.16 `calculateHealthFactor`

```solidity
/// @notice Calculates the health factor for given debt and collateral values.
/// @dev    Pure function (no storage reads, no oracle calls) that allows
///         frontends and off-chain systems to preview health factor changes
///         before submitting transactions. Useful for:
///         - Previewing HF after a proposed mint amount
///         - Previewing HF after a proposed collateral withdrawal
///         - Off-chain liquidation bot pre-checks
///         Formula matches the internal _calculateHealthFactor() exactly.
/// @param  totalDscMinted       Hypothetical DSC debt amount, in wei.
///                              Pass 0 to get type(uint256).max (∞).
/// @param  collateralValueInUsd Hypothetical collateral value in USD, scaled to 1e18.
/// @return                      Resulting health factor scaled to 1e18.
function calculateHealthFactor(
    uint256 totalDscMinted,
    uint256 collateralValueInUsd
) external pure returns (uint256)
```

---

### 2.17 Getter Functions

```solidity
/// @notice Returns the additional precision factor used to convert Chainlink
///         8-decimal prices to 18-decimal format.
/// @return 1e10 (constant)
function getAdditionalFeedPrecision() external pure returns (uint256)

/// @notice Returns the liquidation threshold percentage.
/// @dev    Collateral must be worth at least (threshold/100) × debt to be safe.
/// @return 150 — meaning 150% collateralization is required.
function getLiquidationThreshold() external pure returns (uint256)

/// @notice Returns the liquidation bonus percentage awarded to liquidators.
/// @return 10 — meaning liquidators receive 10% extra collateral as incentive.
function getLiquidationBonus() external pure returns (uint256)

/// @notice Returns the liquidation precision denominator used in bonus calculations.
/// @return 100
function getLiquidationPrecision() external pure returns (uint256)

/// @notice Returns the minimum health factor below which positions are liquidatable.
/// @return 1e18 — representing a health factor of 1.0 in 18-decimal precision.
function getMinHealthFactor() external pure returns (uint256)

/// @notice Returns the base precision constant used throughout the protocol.
/// @return 1e18
function getPrecision() external pure returns (uint256)

/// @notice Returns the address of the DSCoin token contract.
/// @return Address of the immutable DSCoin instance.
function getDsc() external view returns (address)

/// @notice Returns the list of all supported collateral token addresses.
/// @dev    Array is populated at construction and never modified afterward.
///         Iteration over this array is used in getAccountCollateralValue().
/// @return Array of ERC-20 token addresses accepted as collateral.
function getCollateralTokens() external view returns (address[] memory)

/// @notice Returns the amount of a specific collateral token deposited by a user.
/// @param  user   The depositor's address.
/// @param  token  The collateral token address to query.
/// @return        The deposited amount in the token's native decimals.
function getCollateralBalanceOfUser(
    address user,
    address token
) external view returns (uint256)

/// @notice Returns the Chainlink price feed address registered for a collateral token.
/// @param  token  The collateral token address.
/// @return        The AggregatorV3Interface address, or address(0) if not registered.
function getCollateralTokenPriceFeed(address token) external view returns (address)
```

---

## 3. OracleLib.sol

**Contract path:** `contracts/src/libraries/OracleLib.sol`
**Type:** Solidity Library (stateless, no storage)
**Purpose:** Wraps Chainlink price feed reads with a staleness check. Protects the protocol from operating on outdated price data.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  OracleLib
/// @author SC6107 Team
/// @notice Library for safe Chainlink oracle interactions with stale price protection.
/// @dev    If the oracle returns data older than TIMEOUT (3 hours), the calling
///         function reverts with OracleLib__StalePrice. This causes the DSCEngine
///         to pause itself automatically during oracle outages, protecting users
///         from operating at incorrect prices.
///
///         Usage: import and apply using statement in DSCEngine:
///           using OracleLib for AggregatorV3Interface;
///           priceFeed.staleCheckLatestRoundData();
library OracleLib {
```

---

### 3.1 `staleCheckLatestRoundData`

```solidity
/// @notice Fetches the latest price from a Chainlink feed and validates freshness.
/// @dev    Calls AggregatorV3Interface.latestRoundData() and checks that the
///         returned `updatedAt` timestamp is within TIMEOUT (3 hours) of the
///         current block timestamp.
///         If the price is stale, reverts with OracleLib__StalePrice(), which
///         propagates up through DSCEngine and causes the entire transaction to
///         revert. This is an intentional design choice — it is safer to halt
///         the protocol than to operate on incorrect prices.
///         The 3-hour timeout is conservative relative to Chainlink's typical
///         heartbeat (usually 1 hour for major pairs), providing a safety buffer.
/// @param  priceFeed  The Chainlink AggregatorV3Interface to query.
///                    Must be a valid, deployed Chainlink price feed contract.
/// @return roundId          The round ID from the Chainlink aggregator.
/// @return answer           The latest price answer (in feed's native decimals,
///                          typically 8 for USD pairs).
/// @return startedAt        The timestamp when this round started.
/// @return updatedAt        The timestamp of the last price update. Used for
///                          staleness validation.
/// @return answeredInRound  The round in which the answer was computed.
/// @custom:throws OracleLib__StalePrice if block.timestamp - updatedAt > 3 hours.
function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
    public view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    )
```

---

### 3.2 `getTimeout`

```solidity
/// @notice Returns the maximum age (in seconds) of an acceptable price feed response.
/// @dev    Used by tests to verify the timeout constant without hardcoding the
///         value. Returns the TIMEOUT constant (3 hours = 10800 seconds).
/// @return The staleness timeout in seconds (10800 = 3 hours).
function getTimeout() external pure returns (uint256)
```

---

## 4. NatSpec Quick Reference

### Tag Definitions

| Tag | Usage | Description |
|---|---|---|
| `@title` | Contract | One-line name of the contract |
| `@author` | Contract | Author or team name |
| `@notice` | Contract, Function | Plain-English explanation for end users |
| `@dev` | Contract, Function | Technical details for developers |
| `@param` | Function | Documents each input parameter |
| `@return` | Function | Documents each return value |
| `@custom:throws` | Function | Documents revert conditions (custom errors) |
| `@custom:emits` | Function | Documents events emitted on success |

### Error Reference

| Error | Contract | Condition |
|---|---|---|
| `DSCoin__MustBeMoreThanZero` | DSCoin | mint/burn amount is 0 |
| `DSCoin__BurnAmountExceedsBalance` | DSCoin | burn amount > balance |
| `DSCoin__NotZeroAddress` | DSCoin | mint target is address(0) |
| `DSCEngine__NeedsMoreThanZero` | DSCEngine | Any amount parameter is 0 |
| `DSCEngine__TokenNotAllowed` | DSCEngine | Token has no registered price feed |
| `DSCEngine__TransferFailed` | DSCEngine | ERC-20 transfer returned false |
| `DSCEngine__BreaksHealthFactor` | DSCEngine | Operation would drop HF below 1.0 |
| `DSCEngine__MintFailed` | DSCEngine | DSCoin.mint() returned false |
| `DSCEngine__HealthFactorOk` | DSCEngine | Liquidation target is healthy |
| `DSCEngine__HealthFactorNotImproved` | DSCEngine | Liquidation didn't improve target HF |
| `OracleLib__StalePrice` | OracleLib | Price feed not updated in 3+ hours |

### Event Reference

| Event | Parameters | Emitted By |
|---|---|---|
| `CollateralDeposited` | `user, token, amount` (all indexed) | `depositCollateral` |
| `CollateralRedeemed` | `redeemedFrom, redeemedTo, token` (indexed), `amount` | `_redeemCollateral` |
| `DSCMinted` | `user` (indexed), `amount` | `mintDsc` |
| `DSCBurned` | `user` (indexed), `amount` | `_burnDsc` |
| `Liquidated` | `liquidator, user, collateralToken` (indexed), `debtCovered, collateralSeized` | `liquidate` |
| `ProtocolPaused` | `by` (indexed) | `pause` |
| `ProtocolUnpaused` | `by` (indexed) | `unpause` |

---

*Document version: 1.0 | Last updated: 2026*
*Generated from source: contracts/src/DSCoin.sol, contracts/src/DSCEngine.sol, contracts/src/libraries/OracleLib.sol*
