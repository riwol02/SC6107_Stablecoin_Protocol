// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCoin} from "../../src/DSCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

/// @title DSCEngineTest — Comprehensive unit tests for DSCEngine
/// @notice Tests all core protocol functions: deposit, mint, redeem, burn, liquidate.
///         Uses mock tokens and price feeds deployed on a local Anvil fork.
contract DSCEngineTest is Test {
    /*//////////////////////////////////////////////////////////////
                             TEST STATE
    //////////////////////////////////////////////////////////////*/

    DeployDSC deployer;
    DSCoin dsc;
    DSCEngine dscEngine;
    DeployDSC.NetworkConfig config;

    MockERC20 weth;
    MockERC20 wbtc;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;   // 10 WETH
    uint256 public constant AMOUNT_DSC_TO_MINT = 5000 ether; // $5,000 DSC (50% CR at $2000 ETH)
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 150;

    /*//////////////////////////////////////////////////////////////
                               SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();

        weth = MockERC20(config.weth);
        wbtc = MockERC20(config.wbtc);
        ethUsdPriceFeed = MockV3Aggregator(config.ethUsdPriceFeed);
        btcUsdPriceFeed = MockV3Aggregator(config.btcUsdPriceFeed);

        weth.mint(USER, STARTING_ERC20_BALANCE);
        weth.mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        wbtc.mint(USER, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(config.weth);
        priceFeedAddresses.push(config.ethUsdPriceFeed);
        priceFeedAddresses.push(config.btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                         PRICE FEED TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18; // 15 ETH
        // $2,000 * 15 = $30,000
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dscEngine.getUsdValue(config.weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100e18; // $100
        // $100 / $2,000 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(config.weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                       DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(config.weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        MockERC20 randToken = new MockERC20("RAN", "RAN", 18);
        randToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randToken)));
        dscEngine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositedAmount = dscEngine.getTokenAmountFromUsd(config.weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    function testDepositEmitsEvent() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(USER, config.weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT & MINT TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, AMOUNT_DSC_TO_MINT);
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint, dscEngine.getUsdValue(config.weth, AMOUNT_COLLATERAL)
        );
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(config.weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_DSC_TO_MINT);
    }

    /*//////////////////////////////////////////////////////////////
                         BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                       REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(config.weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(config.weth, AMOUNT_COLLATERAL);
        uint256 userBalance = weth.balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit DSCEngine.CollateralRedeemed(USER, USER, config.weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(config.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                   REDEEM COLLATERAL FOR DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateralForDsc(config.weth, 0, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.redeemCollateralForDsc(config.weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                      HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        // 10 ETH @ $2,000 = $20,000 collateral
        // $5,000 DSC minted
        // Threshold: $20,000 * 100 / 150 = $13,333 effective collateral
        // HF = $13,333 / $5,000 = 2.666...
        uint256 expectedHealthFactor = 2666666666666666666;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, healthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        // Crash ETH price to $700 → positions become undercollateralized
        int256 ethUsdUpdatedPrice = 700e8; // $700
        ethUsdPriceFeed.updateAnswer(ethUsdUpdatedPrice);

        // 10 ETH @ $18 = $180 collateral
        // $180 * 150 / 100 = $270 effective collateral
        // HF = $270 / $5,000 = 0.054
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        assert(userHealthFactor < MIN_HEALTH_FACTOR);
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    modifier liquidated() {
        // User deposits 10 ETH and mints $5,000 DSC at $2,000/ETH (HF = 6.0)
        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        // ETH crashes to $700 → HF drops below 1
        ethUsdPriceFeed.updateAnswer(700e8);

        // Liquidator obtains DSC and approves
        uint256 debtToCover = AMOUNT_DSC_TO_MINT;
        uint256 liquidatorCollateral = 1000 ether;
        weth.mint(LIQUIDATOR, liquidatorCollateral);
        vm.startPrank(LIQUIDATOR);
        weth.approve(address(dscEngine), liquidatorCollateral);
        dscEngine.depositCollateralAndMintDsc(config.weth, liquidatorCollateral, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dscEngine), debtToCover);
        dscEngine.liquidate(config.weth, USER, debtToCover);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = weth.balanceOf(LIQUIDATOR);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(config.weth, AMOUNT_DSC_TO_MINT)
            + (dscEngine.getTokenAmountFromUsd(config.weth, AMOUNT_DSC_TO_MINT) / 10);
        assertEq(liquidatorWethBalance, expectedWeth + STARTING_ERC20_BALANCE);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // User had 10 ETH deposited. ~305 WETH seized → user has remaining collateral
        uint256 amountLiquidated = dscEngine.getTokenAmountFromUsd(config.weth, AMOUNT_DSC_TO_MINT)
            + (dscEngine.getTokenAmountFromUsd(config.weth, AMOUNT_DSC_TO_MINT) / 10);
        uint256 usdAmountLiquidated = dscEngine.getUsdValue(config.weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd =
            dscEngine.getUsdValue(config.weth, AMOUNT_COLLATERAL) - usdAmountLiquidated;

        (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_DSC_TO_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 debtToCover = 1 ether;
        weth.mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        vm.startPrank(LIQUIDATOR);
        weth.approve(address(dscEngine), STARTING_ERC20_BALANCE);
        dscEngine.depositCollateralAndMintDsc(config.weth, STARTING_ERC20_BALANCE, debtToCover);
        dsc.approve(address(dscEngine), debtToCover);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(config.weth, USER, debtToCover);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       PAUSE / EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanPause() public {
        address owner = dscEngine.owner();
        vm.prank(owner);
        dscEngine.pause();
        assertTrue(dscEngine.paused());
    }

    function testNonOwnerCannotPause() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.pause();
    }

    function testDepositRevertsWhenPaused() public {
        address owner = dscEngine.owner();
        vm.prank(owner);
        dscEngine.pause();

        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert();
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], config.weth);
        assertEq(collateralTokens[1], config.wbtc);
    }

    function testGetDsc() public view {
        assertEq(dscEngine.getDsc(), address(dsc));
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, config.weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }
}
