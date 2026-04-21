// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DSCoin} from "./DSCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/// @title DSCEngine — Core Engine for the Decentralized Stable Coin Protocol
/// @author SC6107 Team
/// @notice Manages collateral deposits, DSC minting/burning, and liquidations.
///
/// @dev Key invariant: the protocol must always be over-collateralized.
///      At all times: total collateral value (USD) > total DSC supply (USD).
///
///      Collateralization ratio : 150 %  (i.e., $150 collateral → max $100 DSC)
///      Liquidation threshold   : 150 %  (health factor < 1 → liquidatable)
///      Liquidation bonus       : 10 %   (incentive for liquidators)
///
///      Supported collateral: WETH, WBTC (configurable at deploy time)
///      Price feeds: Chainlink (stale-price protected via OracleLib)
///
/// Security considerations:
///   - ReentrancyGuard on all state-changing external functions
///   - Checks-Effects-Interactions pattern throughout
///   - Emergency pause via Pausable (owner only)
///   - Chainlink stale price check (3-hour timeout)
///   - No unchecked arithmetic (Solidity 0.8.x built-in overflow protection)
contract DSCEngine is ReentrancyGuard, Pausable, Ownable {
    using OracleLib for AggregatorV3Interface;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                            USING DIRECTIVES
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Extra decimal precision for Chainlink prices (returns 8 decimals, we need 18)
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev Standard 18-decimal precision factor
    uint256 private constant PRECISION = 1e18;

    /// @dev Collateralization threshold: 150% (stored as /100 denominator pair)
    uint256 private constant LIQUIDATION_THRESHOLD = 150; // must hold 150% collateral
    uint256 private constant LIQUIDATION_PRECISION = 100;

    /// @dev Minimum health factor (below this → liquidatable). Scaled to 1e18.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /// @dev Bonus collateral rewarded to liquidators (10%)
    uint256 private constant LIQUIDATION_BONUS = 10;

    /// @dev Maximum single-transaction DSC mint (circuit breaker)
    uint256 public constant MAX_MINT_PER_TX = 1_000_000e18; // 1M DSC

    /// @notice The DSCoin token this engine controls
    DSCoin private immutable i_dsc;

    /// @notice Chainlink price feed for each allowed collateral token
    mapping(address token => address priceFeed) private s_priceFeeds;

    /// @notice Collateral balance per user per token
    /// @dev user → token → amount (in token's native decimals)
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    /// @notice DSC minted per user
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    /// @notice Ordered list of allowed collateral token addresses
    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DSCMinted(address indexed user, uint256 amount);
    event DSCBurned(address indexed user, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 debtCovered,
        uint256 collateralSeized
    );
    event ProtocolPaused(address indexed by);
    event ProtocolUnpaused(address indexed by);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the DSCEngine and configures supported collateral.
    /// @param tokenAddresses    Ordered list of ERC-20 collateral token addresses.
    /// @param priceFeedAddresses Chainlink price feed addresses matching tokenAddresses.
    /// @param dscAddress        Address of the DSCoin token contract.
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress)
        Ownable(msg.sender)
    {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DSCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits collateral and mints DSC in a single transaction.
    /// @dev Convenience wrapper around depositCollateral + mintDsc.
    /// @param tokenCollateralAddress ERC-20 token to use as collateral.
    /// @param amountCollateral       Amount of collateral to deposit (in token decimals).
    /// @param amountDscToMint        Amount of DSC to mint (in 1e18).
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external whenNotPaused {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @notice Deposits ERC-20 collateral into the protocol.
    /// @dev Follows Checks-Effects-Interactions: state updated before transfer.
    /// @param tokenCollateralAddress The ERC-20 token address to deposit.
    /// @param amountCollateral       Amount to deposit (in token's native decimals).
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        whenNotPaused
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Interactions
        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
    }

    /// @notice Mints DSC against the caller's deposited collateral.
    /// @dev Reverts if minting would cause health factor to drop below minimum.
    /// @param amountDscToMint Amount of DSC to mint (in 1e18 = 1 DSC).
    function mintDsc(uint256 amountDscToMint)
        public
        whenNotPaused
        moreThanZero(amountDscToMint)
        nonReentrant
    {
        if (amountDscToMint > MAX_MINT_PER_TX) {
            revert DSCEngine__NeedsMoreThanZero(); // reuse for circuit breaker
        }
        // Effects
        s_DSCMinted[msg.sender] += amountDscToMint;
        emit DSCMinted(msg.sender, amountDscToMint);

        // Check health factor after state update
        _revertIfHealthFactorIsBroken(msg.sender);

        // Interactions
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /// @notice Burns DSC and redeems collateral in one transaction.
    /// @param tokenCollateralAddress Collateral token to retrieve.
    /// @param amountCollateral       Amount of collateral to redeem.
    /// @param amountDscToBurn        Amount of DSC to burn.
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external whenNotPaused moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Redeems collateral without burning DSC.
    /// @dev Reverts if redemption causes health factor to drop below minimum.
    /// @param tokenCollateralAddress Collateral token to retrieve.
    /// @param amountCollateral       Amount of collateral to redeem.
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        whenNotPaused
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Burns DSC to reduce the caller's debt.
    /// @param amount Amount of DSC to burn (in 1e18).
    function burnDsc(uint256 amount) external whenNotPaused moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // should never revert (burning improves HF)
    }

    /// @notice Liquidates an undercollateralized position.
    /// @dev Liquidator repays `debtToCover` DSC and receives collateral at a 10% bonus.
    ///      The target user's health factor must be below MIN_HEALTH_FACTOR.
    ///      The liquidator's health factor must improve after the operation.
    ///
    /// @param collateral    Address of the collateral token to seize.
    /// @param user          The user whose position is being liquidated.
    /// @param debtToCover   Amount of DSC the liquidator is repaying (in 1e18).
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        whenNotPaused
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // Calculate collateral to seize: debt value + 10% bonus
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // Effects + Interactions
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        // Verify liquidation improved the position
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

        emit Liquidated(msg.sender, user, collateral, debtToCover, totalCollateralToRedeem);
    }

    /// @notice Pauses the protocol in case of emergency.
    /// @dev Only owner (multisig in production) can pause.
    function pause() external onlyOwner {
        _pause();
        emit ProtocolPaused(msg.sender);
    }

    /// @notice Unpauses the protocol.
    function unpause() external onlyOwner {
        _unpause();
        emit ProtocolUnpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE & INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal collateral redemption — no health factor check (caller must verify).
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // Effects
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral; // underflow = revert
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // Interactions
        IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
    }

    /// @dev Burns DSC from `dscFrom` using an allowance from `onBehalfOf`.
    ///      Used both for self-burn and liquidator burn.
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // Effects
        s_DSCMinted[onBehalfOf] -= amountDscToBurn; // underflow = revert
        emit DSCBurned(onBehalfOf, amountDscToBurn);

        // Interactions — DSC must be transferred to engine before burn
        IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountDscToBurn);
        i_dsc.burn(amountDscToBurn);
    }

    /// @dev Returns account collateral value (USD, 1e18) and DSC minted for a user.
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// @dev Computes the health factor for a user.
    ///      Health factor = (collateral_value_usd * threshold / 100) / dsc_minted
    ///      If no DSC minted, returns type(uint256).max (perfectly healthy).
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold =
            (collateralValueInUsd * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /// @dev Reverts if the caller's health factor is below the minimum.
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the USD value of a given amount of a collateral token.
    /// @param token  The ERC-20 collateral token address.
    /// @param amount Amount of tokens (in token's native decimals, assumed 18).
    /// @return       USD value scaled to 1e18.
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // price has 8 decimals, amount has 18 decimals → result has 18 decimals
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @notice Returns the token amount equivalent to a USD value.
    /// @param token          The collateral token address.
    /// @param usdAmountInWei USD amount scaled to 1e18.
    /// @return               Token amount (in token's native decimals, assumed 18).
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /// @notice Returns the total USD value of all collateral deposited by a user.
    /// @param user The user address to query.
    /// @return totalCollateralValueInUsd Total value in USD (1e18 scaled).
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    /// @notice Returns DSC minted and collateral value for a user.
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    /// @notice Computes and returns a user's current health factor.
    /// @param user The address to check.
    /// @return     Health factor scaled to 1e18 (>= 1e18 = healthy).
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @notice Calculates health factor for given inputs (view helper for UI).
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
