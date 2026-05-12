// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DSCoin} from "../../src/DSCoin.sol";

/// @title DSCoinTest — Unit tests for DSCoin ERC-20 stablecoin token
contract DSCoinTest is Test {
    DSCoin dsc;
    address public USER = makeAddr("user");
    address public OWNER = makeAddr("owner");

    function setUp() external {
        vm.prank(OWNER);
        dsc = new DSCoin();
    }

    /*//////////////////////////////////////////////////////////////
                           MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DSCoin.DSCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(this), 0);
    }

    function testMustNotMintToZeroAddress() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DSCoin.DSCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, 100 ether);
    }

    function testCanMint() public {
        vm.prank(dsc.owner());
        bool success = dsc.mint(USER, 100 ether);
        assertTrue(success);
        assertEq(dsc.balanceOf(USER), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function testMustBurnMoreThanZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(dsc.owner(), 100 ether);
        vm.expectRevert(DSCoin.DSCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(dsc.owner(), 100 ether);
        vm.expectRevert(DSCoin.DSCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(101 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerCanBurn() public {
        vm.prank(dsc.owner());
        dsc.mint(USER, 100 ether);

        vm.prank(USER);
        vm.expectRevert();
        dsc.burn(50 ether);
    }

    function testCanBurn() public {
        vm.startPrank(dsc.owner());
        dsc.mint(dsc.owner(), 100 ether);
        dsc.burn(100 ether);
        vm.stopPrank();
        assertEq(dsc.balanceOf(dsc.owner()), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-20 METADATA
    //////////////////////////////////////////////////////////////*/

    function testNameAndSymbol() public view {
        assertEq(dsc.name(), "Decentralized Stable Coin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
    }
}
