// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/// ERC-20 stablecoin pegged 1:1 to USD
contract DSCoin is ERC20Burnable, Ownable {

    error DSCoin__MustBeMoreThanZero();
    error DSCoin__BurnAmountExceedsBalance();
    error DSCoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable(msg.sender) {}

    /// Burns DSC tokens from the caller's balance
    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount == 0) {
            revert DSCoin__MustBeMoreThanZero();
        }
        if (balance < amount) {
            revert DSCoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    /// Mints new DSC tokens to the specified address
    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DSCoin__NotZeroAddress();
        }
        if (amount == 0) {
            revert DSCoin__MustBeMoreThanZero();
        }
        _mint(to, amount);
        return true;
    }
}