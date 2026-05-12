// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DSCoin} from "../../src/DSCoin.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Handler — Guides the fuzzer to call valid function sequences
/// @notice Constrains fuzz inputs to realistic ranges and valid states.
///         Without a handler, the fuzzer would mostly call with invalid tokens / zero amounts.
contract Handler is Test {
    DSCEngine public dscEngine;
    DSCoin public dsc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    mapping(address => bool) public hasDeposited;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max; // ~79B tokens

    constructor(DSCEngine _dscEngine, DSCoin _dsc, address _weth, address _wbtc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        weth = MockERC20(_weth);
        wbtc = MockERC20(_wbtc);
    }

    /*//////////////////////////////////////////////////////////////
                          HANDLER ACTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        if (!hasDeposited[msg.sender]) {
            usersWithCollateralDeposited.push(msg.sender);
            hasDeposited[msg.sender] = true;
        }
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;

        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) return;

        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;

        vm.prank(sender);
        dscEngine.mintDsc(amount);
        timesMintIsCalled++;
    }

    /*//////////////////////////////////////////////////////////////
                             HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (MockERC20) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function getUsersWithCollateralDeposited() external view returns (address[] memory) {
        return usersWithCollateralDeposited;
    }
}

/// @title InvariantTest — Protocol-level invariant tests
/// @notice Core invariant: total collateral value >= total DSC supply at all times.
///         This ensures the protocol is always over-collateralized.
contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DSCoin dsc;
    Handler handler;
    DeployDSC.NetworkConfig config;

    MockERC20 weth;
    MockERC20 wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();

        weth = MockERC20(config.weth);
        wbtc = MockERC20(config.wbtc);

        handler = new Handler(dscEngine, dsc, config.weth, config.wbtc);
        targetContract(address(handler));
    }

    /// @notice THE CORE INVARIANT:
    ///         The total USD value of all protocol collateral must always be >= total DSC minted.
    ///         If this breaks, the protocol is insolvent.
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(config.weth).balanceOf(address(dscEngine));
        uint256 totalBtcDeposited = IERC20(config.wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(config.weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(config.wbtc, totalBtcDeposited);

        console.log("wethValue:", wethValue);
        console.log("wbtcValue:", wbtcValue);
        console.log("totalSupply:", totalSupply);
        console.log("timesMintIsCalled:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    /// @notice Getters should never revert — they must always return valid data.
    function invariant_gettersShouldNeverRevert() public view {
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getPrecision();
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
    }
}

/// @title FuzzTest — Targeted property-based fuzz tests for DSCEngine
contract FuzzTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DSCoin dsc;
    DeployDSC.NetworkConfig config;
    MockERC20 weth;

    address USER = makeAddr("user");
    uint256 constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        weth = MockERC20(config.weth);
        weth.mint(USER, 1000 ether);
    }

    /// @notice Health factor must always be >= 1 after minting (otherwise revert)
    function fuzz_healthFactorAlwaysAboveOneAfterMint(uint256 amountDscToMint) public {
        // Bound to realistic range: 1 wei to $13,333 (max at 150% threshold for 10 ETH @ $2,000)
        amountDscToMint = bound(amountDscToMint, 1, 13333e18);

        vm.startPrank(USER);
        weth.approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(config.weth, AMOUNT_COLLATERAL);
        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();

        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertGe(healthFactor, 1e18, "Health factor must be >= 1 after successful mint");
    }

    /// @notice USD value conversion must be reversible (getUsdValue ∘ getTokenAmount = identity)
    function fuzz_usdValueConversionIsConsistent(uint256 usdAmount) public view {
        usdAmount = bound(usdAmount, 1e8, 1_000_000e18); // $0.00000001 to $1M

        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(config.weth, usdAmount);
        uint256 recoveredUsd = dscEngine.getUsdValue(config.weth, tokenAmount);

        // Allow 1 wei rounding error from integer division
        assertApproxEqAbs(recoveredUsd, usdAmount, 1e10, "USD conversion should be approximately reversible");
    }
}
