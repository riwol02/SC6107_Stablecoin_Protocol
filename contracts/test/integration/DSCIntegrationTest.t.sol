// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCoin} from "../../src/DSCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DSCIntegrationTest — End-to-end user journey tests
/// @notice Simulates complete real-world usage scenarios across multiple users.
///         These tests verify the protocol behaves correctly as a whole system,
///         not just individual function calls.
contract DSCIntegrationTest is Test {
    DeployDSC deployer;
    DSCoin dsc;
    DSCEngine engine;
    DeployDSC.NetworkConfig config;

    MockERC20 weth;
    MockV3Aggregator ethFeed;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 constant ETH_PRICE    = 2000e8;   // $2,000 per ETH (Chainlink 8 decimals)
    uint256 constant WETH_AMOUNT  = 10 ether; // 10 WETH = $20,000

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();

        weth    = MockERC20(config.weth);
        ethFeed = MockV3Aggregator(config.ethUsdPriceFeed);

        // Mint WETH to test users
        weth.mint(alice,   100 ether);
        weth.mint(bob,     100 ether);
        weth.mint(carol,   500 ether);  // carol is a well-capitalised liquidator
    }

    /*//////////////////////////////////////////////////////////////
              SCENARIO 1: Happy Path — Full lifecycle
    //////////////////////////////////////////////////////////////*/

    /// @notice Alice deposits collateral, mints DSC, burns DSC, redeems collateral.
    function test_scenario_happyPath() public {
        // ── Alice deposits 10 WETH and mints $5,000 DSC ──────────────────────
        vm.startPrank(alice);
        weth.approve(address(engine), WETH_AMOUNT);
        engine.depositCollateralAndMintDsc(config.weth, WETH_AMOUNT, 5000 ether);
        vm.stopPrank();

        assertEq(dsc.balanceOf(alice), 5000 ether, "Alice should have 5000 DSC");

        uint256 hfAfterMint = engine.getHealthFactor(alice);
        // HF = ($20,000 * 100 / 150) / $5,000 = 2.666...
        assertEq(hfAfterMint, 2666666666666666666, "HF should be ~2.66 after minting");

        // ── Alice burns 2,500 DSC ─────────────────────────────────────────────
        vm.startPrank(alice);
        dsc.approve(address(engine), 2500 ether);
        engine.burnDsc(2500 ether);
        vm.stopPrank();

        assertEq(dsc.balanceOf(alice), 2500 ether, "Alice should have 2500 DSC after burn");

        uint256 hfAfterBurn = engine.getHealthFactor(alice);
        assertGt(hfAfterBurn, hfAfterMint, "HF should improve after burning DSC");

        // ── Alice redeems 5 WETH ──────────────────────────────────────────────
        vm.startPrank(alice);
        engine.redeemCollateral(config.weth, 5 ether);
        vm.stopPrank();

        uint256 remaining = engine.getCollateralBalanceOfUser(alice, config.weth);
        assertEq(remaining, 5 ether, "5 WETH should remain deposited");

        // Health factor still above 1
        uint256 hfFinal = engine.getHealthFactor(alice);
        assertGe(hfFinal, 1e18, "HF must stay healthy after partial redemption");

        console.log("Scenario 1 complete:");
        console.log("  DSC balance:", dsc.balanceOf(alice) / 1e18);
        console.log("  WETH deposited:", remaining / 1e18);
        console.log("  Health factor:", hfFinal / 1e18);
    }

    /*//////////////////////////////////////////////////////////////
          SCENARIO 2: Liquidation — Price crash triggers liquidation
    //////////////////////////////////////////////////////////////*/

    /// @notice Bob mints at maximum safe ratio, price crashes, Carol liquidates him.
    function test_scenario_liquidation() public {
        // ── Bob deposits 10 WETH and mints $13,333 DSC (near max at $2k ETH) ─
        uint256 maxSafeMint = 13_333 ether; // just under 150% threshold
        vm.startPrank(bob);
        weth.approve(address(engine), WETH_AMOUNT);
        engine.depositCollateralAndMintDsc(config.weth, WETH_AMOUNT, maxSafeMint);
        vm.stopPrank();

        uint256 hfBefore = engine.getHealthFactor(bob);
        assertGt(hfBefore, 1e18, "Bob should be healthy before price crash");
        console.log("Bob HF before crash:", hfBefore * 100 / 1e18, "/ 100");

        // ── ETH crashes from $2,000 to $1,800 ──────────────────────────────────
        ethFeed.updateAnswer(1800e8);

        uint256 hfAfterCrash = engine.getHealthFactor(bob);
        assertLt(hfAfterCrash, 1e18, "Bob should be liquidatable after crash");
        console.log("Bob HF after crash:", hfAfterCrash * 100 / 1e18, "/ 100");

        // ── Carol liquidates Bob, covering $5,000 of his debt ────────────────
        uint256 debtToCover = 5000 ether;

        // Carol needs DSC to cover Bob's debt — she deposits her own collateral first
        vm.startPrank(carol);
        weth.approve(address(engine), 100 ether);
        engine.depositCollateralAndMintDsc(config.weth, 100 ether, debtToCover);

        uint256 carolWethBefore = weth.balanceOf(carol);

        dsc.approve(address(engine), debtToCover);
        engine.liquidate(config.weth, bob, debtToCover);
        vm.stopPrank();

        uint256 carolWethAfter = weth.balanceOf(carol);
        uint256 wethSeized = carolWethAfter - carolWethBefore;

        // At $1800/ETH: $5,000 / $1800 ≈ 2.77 WETH + 10% bonus ≈ 3.05 WETH
        console.log("Carol seized WETH:", wethSeized * 100 / 1e18, "/ 100 (x0.01 ETH units)");
        assertGt(wethSeized, 3 ether, "Carol should receive > 3 WETH for covering $5k debt");

        // Bob's debt should have decreased
        (uint256 bobDebtAfter,) = engine.getAccountInformation(bob);
        assertEq(bobDebtAfter, maxSafeMint - debtToCover, "Bob debt reduced by amount covered");

        console.log("Scenario 2 complete:");
        console.log("  Bob remaining debt:", bobDebtAfter / 1e18, "DSC");
        console.log("  Carol WETH seized:", wethSeized / 1e18, "WETH");
    }

    /*//////////////////////////////////////////////////////////////
          SCENARIO 3: Multi-user — Protocol handles multiple positions
    //////////////////////////////////////////////////////////////*/

    /// @notice Multiple users hold positions; protocol-level invariant holds.
    function test_scenario_multiUser_invariantHolds() public {
        // Alice: conservative position
        vm.startPrank(alice);
        weth.approve(address(engine), 20 ether);
        engine.depositCollateralAndMintDsc(config.weth, 20 ether, 5000 ether);
        vm.stopPrank();

        // Bob: aggressive position
        vm.startPrank(bob);
        weth.approve(address(engine), 10 ether);
        engine.depositCollateralAndMintDsc(config.weth, 10 ether, 10000 ether);
        vm.stopPrank();

        // Check core invariant: total collateral USD ≥ total DSC supply
        uint256 totalDscSupply = dsc.totalSupply();
        uint256 totalWethInProtocol = IERC20(config.weth).balanceOf(address(engine));
        uint256 totalCollateralUsd = engine.getUsdValue(config.weth, totalWethInProtocol);

        console.log("Total DSC minted:", totalDscSupply / 1e18);
        console.log("Total WETH locked:", totalWethInProtocol / 1e18);
        console.log("Total collateral USD:", totalCollateralUsd / 1e18);

        assertGe(totalCollateralUsd, totalDscSupply, "CORE INVARIANT: collateral >= supply");

        // Both users healthy
        assertGe(engine.getHealthFactor(alice), 1e18);
        assertGe(engine.getHealthFactor(bob), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
          SCENARIO 4: Emergency Pause — Owner pauses, users cannot interact
    //////////////////////////////////////////////////////////////*/

    function test_scenario_emergencyPause() public {
        address owner = engine.owner();

        // Alice establishes position before pause
        vm.startPrank(alice);
        weth.approve(address(engine), 10 ether);
        engine.depositCollateral(config.weth, 10 ether);
        vm.stopPrank();

        // Owner pauses in response to incident
        vm.prank(owner);
        engine.pause();
        assertTrue(engine.paused(), "Protocol should be paused");

        // Alice cannot deposit while paused
        vm.startPrank(alice);
        weth.approve(address(engine), 5 ether);
        vm.expectRevert();
        engine.depositCollateral(config.weth, 5 ether);
        vm.stopPrank();

        // Bob cannot mint while paused
        vm.prank(bob);
        vm.expectRevert();
        engine.mintDsc(1000 ether);

        // Owner unpauses after incident resolved
        vm.prank(owner);
        engine.unpause();
        assertFalse(engine.paused(), "Protocol should be unpaused");

        // Alice can deposit again
        vm.startPrank(alice);
        weth.approve(address(engine), 5 ether);
        engine.depositCollateral(config.weth, 5 ether);
        vm.stopPrank();

        console.log("Scenario 4: Emergency pause/unpause works correctly");
    }

    /*//////////////////////////////////////////////////////////////
          SCENARIO 5: Stale Oracle — Transactions revert on stale price
    //////////////////////////////////////////////////////////////*/

    function test_scenario_staleOracleReverts() public {
        // Fast-forward 4 hours past last oracle update
        vm.warp(block.timestamp + 4 hours);

        vm.startPrank(alice);
        weth.approve(address(engine), 10 ether);

        // depositCollateral reads the price feed — should revert on stale price
        vm.expectRevert();
        engine.depositCollateralAndMintDsc(config.weth, 10 ether, 1000 ether);
        vm.stopPrank();

        console.log("Scenario 5: Stale oracle protection works correctly");
    }
}
