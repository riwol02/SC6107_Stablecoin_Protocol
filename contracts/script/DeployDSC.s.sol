// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DSCoin} from "../src/DSCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

/// @title DeployDSC — Deployment script for the DSC Protocol
/// @notice Handles deployment on both local anvil and live testnets.
///         On local chains: deploys mock WETH, WBTC, and price feeds.
///         On Sepolia: uses real Chainlink feeds and token addresses.
contract DeployDSC is Script {
    /*//////////////////////////////////////////////////////////////
                          NETWORK CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/

    // Sepolia testnet Chainlink price feeds
    address constant SEPOLIA_ETH_USD_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant SEPOLIA_BTC_USD_PRICE_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    // Sepolia WETH / WBTC (ERC-20 wrappers)
    address constant SEPOLIA_WETH = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;
    address constant SEPOLIA_WBTC = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

    // Initial mock prices (8 decimals like Chainlink)
    int256 constant MOCK_ETH_USD_PRICE = 2000e8; // $2,000
    int256 constant MOCK_BTC_USD_PRICE = 60000e8; // $60,000

    struct NetworkConfig {
        address weth;
        address wbtc;
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                             DEPLOY LOGIC
    //////////////////////////////////////////////////////////////*/

    function run() external returns (DSCoin, DSCEngine, NetworkConfig memory) {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }

        NetworkConfig memory config = activeNetworkConfig;

        vm.startBroadcast(config.deployerKey);

        // 1. Deploy the stablecoin token
        DSCoin dsc = new DSCoin();

        // 2. Configure collateral tokens and price feeds
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = config.weth;
        tokenAddresses[1] = config.wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = config.ethUsdPriceFeed;
        priceFeedAddresses[1] = config.btcUsdPriceFeed;

        // 3. Deploy the core engine
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // 4. Transfer DSCoin ownership to the engine
        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }

    /*//////////////////////////////////////////////////////////////
                         NETWORK CONFIGS
    //////////////////////////////////////////////////////////////*/

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: SEPOLIA_WETH,
            wbtc: SEPOLIA_WBTC,
            ethUsdPriceFeed: SEPOLIA_ETH_USD_PRICE_FEED,
            btcUsdPriceFeed: SEPOLIA_BTC_USD_PRICE_FEED,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // Return existing config if already deployed
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        uint256 deployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default

        vm.startBroadcast(deployerKey);

        // Deploy mock tokens
        MockERC20 mockWeth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 mockWbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Deploy mock price feeds
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(MOCK_ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(MOCK_BTC_USD_PRICE);

        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(mockWeth),
            wbtc: address(mockWbtc),
            ethUsdPriceFeed: address(ethUsdPriceFeed),
            btcUsdPriceFeed: address(btcUsdPriceFeed),
            deployerKey: deployerKey
        });
    }
}
