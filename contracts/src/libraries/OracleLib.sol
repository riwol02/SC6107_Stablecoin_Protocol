// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {

    error OracleLib__StalePrice();

    /// @dev Maximum age of a price feed response before considered stale = 3 hours
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();

        uint256 secondsSinceUpdate = block.timestamp - updatedAt;
        if (secondsSinceUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
    }

    /// Returns the timeout duration for stale price detection
    function getTimeout() external pure returns (uint256) {
        return TIMEOUT;
    }
}
