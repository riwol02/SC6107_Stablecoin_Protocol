export const DSC_ENGINE_ABI = [
  {
    "type": "constructor",
    "inputs": [
      {"name": "tokenAddresses", "type": "address[]"},
      {"name": "priceFeedAddresses", "type": "address[]"},
      {"name": "dscAddress", "type": "address"}
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "CollateralDeposited",
    "inputs": [
      {"name": "user", "type": "address", "indexed": true},
      {"name": "token", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256", "indexed": true}
    ]
  },
  {
    "type": "event",
    "name": "CollateralRedeemed",
    "inputs": [
      {"name": "redeemedFrom", "type": "address", "indexed": true},
      {"name": "redeemedTo", "type": "address", "indexed": true},
      {"name": "token", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256"}
    ]
  },
  {
    "type": "event",
    "name": "DSCMinted",
    "inputs": [
      {"name": "user", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256"}
    ]
  },
  {
    "type": "event",
    "name": "DSCBurned",
    "inputs": [
      {"name": "user", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256"}
    ]
  },
  {
    "type": "event",
    "name": "Liquidated",
    "inputs": [
      {"name": "liquidator", "type": "address", "indexed": true},
      {"name": "user", "type": "address", "indexed": true},
      {"name": "collateralToken", "type": "address", "indexed": true},
      {"name": "debtCovered", "type": "uint256"},
      {"name": "collateralSeized", "type": "uint256"}
    ]
  },
  {
    "type": "function",
    "name": "depositCollateralAndMintDsc",
    "inputs": [
      {"name": "tokenCollateralAddress", "type": "address"},
      {"name": "amountCollateral", "type": "uint256"},
      {"name": "amountDscToMint", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "depositCollateral",
    "inputs": [
      {"name": "tokenCollateralAddress", "type": "address"},
      {"name": "amountCollateral", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "redeemCollateralForDsc",
    "inputs": [
      {"name": "tokenCollateralAddress", "type": "address"},
      {"name": "amountCollateral", "type": "uint256"},
      {"name": "amountDscToBurn", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "redeemCollateral",
    "inputs": [
      {"name": "tokenCollateralAddress", "type": "address"},
      {"name": "amountCollateral", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "mintDsc",
    "inputs": [{"name": "amountDscToMint", "type": "uint256"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "burnDsc",
    "inputs": [{"name": "amount", "type": "uint256"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "liquidate",
    "inputs": [
      {"name": "collateral", "type": "address"},
      {"name": "user", "type": "address"},
      {"name": "debtToCover", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getAccountInformation",
    "inputs": [{"name": "user", "type": "address"}],
    "outputs": [
      {"name": "totalDscMinted", "type": "uint256"},
      {"name": "collateralValueInUsd", "type": "uint256"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getHealthFactor",
    "inputs": [{"name": "user", "type": "address"}],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getUsdValue",
    "inputs": [
      {"name": "token", "type": "address"},
      {"name": "amount", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTokenAmountFromUsd",
    "inputs": [
      {"name": "token", "type": "address"},
      {"name": "usdAmountInWei", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCollateralBalanceOfUser",
    "inputs": [
      {"name": "user", "type": "address"},
      {"name": "token", "type": "address"}
    ],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCollateralTokens",
    "inputs": [],
    "outputs": [{"name": "", "type": "address[]"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAccountCollateralValue",
    "inputs": [{"name": "user", "type": "address"}],
    "outputs": [{"name": "totalCollateralValueInUsd", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "calculateHealthFactor",
    "inputs": [
      {"name": "totalDscMinted", "type": "uint256"},
      {"name": "collateralValueInUsd", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getLiquidationThreshold",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getLiquidationBonus",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getMinHealthFactor",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getDsc",
    "inputs": [],
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "paused",
    "inputs": [],
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view"
  }
];

export const ERC20_ABI = [
  {
    "type": "function",
    "name": "approve",
    "inputs": [
      {"name": "spender", "type": "address"},
      {"name": "amount", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "allowance",
    "inputs": [
      {"name": "owner", "type": "address"},
      {"name": "spender", "type": "address"}
    ],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "balanceOf",
    "inputs": [{"name": "account", "type": "address"}],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "decimals",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint8"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "symbol",
    "inputs": [],
    "outputs": [{"name": "", "type": "string"}],
    "stateMutability": "view"
  }
];
