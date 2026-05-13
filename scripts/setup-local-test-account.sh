#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
TEST_ACCOUNT="${TEST_ACCOUNT:-0xa208DCE30A29B85099e8acDcc696276E4932894b}"
ANVIL_PRIVATE_KEY="${ANVIL_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

LOCAL_ETH_BALANCE_HEX="${LOCAL_ETH_BALANCE_HEX:-0x3635C9ADC5DEA00000}" # 1000 ETH
WETH_AMOUNT="${WETH_AMOUNT:-100000000000000000000}" # 100 WETH, 18 decimals
WBTC_AMOUNT="${WBTC_AMOUNT:-10000000000}" # 100 WBTC, 8 decimals

DSC_ENGINE="0x0165878A594ca255338adfa4d48449f69242Eb8F"
DSC_COIN="0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"
WETH="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
WBTC="0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"

echo "Checking local Anvil RPC at ${RPC_URL}..."
cast block-number --rpc-url "${RPC_URL}" >/dev/null

echo "Deploying DSC protocol contracts..."
forge script contracts/script/DeployDSC.s.sol \
  --rpc-url "${RPC_URL}" \
  --broadcast \
  -vvvv

echo "Funding test account with local ETH gas..."
cast rpc anvil_setBalance "${TEST_ACCOUNT}" "${LOCAL_ETH_BALANCE_HEX}" --rpc-url "${RPC_URL}" >/dev/null

echo "Minting mock WETH to ${TEST_ACCOUNT}..."
cast send "${WETH}" "mint(address,uint256)" "${TEST_ACCOUNT}" "${WETH_AMOUNT}" \
  --private-key "${ANVIL_PRIVATE_KEY}" \
  --rpc-url "${RPC_URL}" >/dev/null

echo "Minting mock WBTC to ${TEST_ACCOUNT}..."
cast send "${WBTC}" "mint(address,uint256)" "${TEST_ACCOUNT}" "${WBTC_AMOUNT}" \
  --private-key "${ANVIL_PRIVATE_KEY}" \
  --rpc-url "${RPC_URL}" >/dev/null

echo
echo "Local setup complete."
echo "Test account: ${TEST_ACCOUNT}"
echo "DSCEngine:    ${DSC_ENGINE}"
echo "DSCoin:       ${DSC_COIN}"
echo "WETH:         ${WETH} ($(cast call "${WETH}" "balanceOf(address)(uint256)" "${TEST_ACCOUNT}" --rpc-url "${RPC_URL}"))"
echo "WBTC:         ${WBTC} ($(cast call "${WBTC}" "balanceOf(address)(uint256)" "${TEST_ACCOUNT}" --rpc-url "${RPC_URL}"))"
echo
echo "Open the frontend with:"
echo "  cd frontend && npm start"
