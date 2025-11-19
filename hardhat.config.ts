import * as dotenv from "dotenv";

import 'hardhat-deploy';
import 'hardhat-tracer';
import 'hardhat-watcher';
import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ignition-ethers";
import 'hardhat-contract-sizer';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    },
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      forking: {
        enabled: false, // Enable forking for Ethereum mainnet
        // Use Ethereum mainnet to access real Uniswap V2 Router
        url: process.env.MAINNET_RPC_URL || "https://restless-ancient-mound.quiknode.pro/20fb2886d7e437de345ce39e98151180241816af/",
        blockNumber: 18000000, // Ethereum mainnet block (Sep 2023 - after EIP-1559, has Uniswap V2)
      },
      // Explicitly set hardfork to support EIP-1559
      hardfork: "london", // London hardfork introduced EIP-1559
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
          apiUrl: "https://api.etherscan.io/v2/api?chainid=11155111"
        },
      },
      gasPrice: 2000000000,
      gasMultiplier: 1.5,
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1,
      gasPrice: 30000000000, // 30 gwei
      gasMultiplier: 1.2,
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
        },
      },
    }
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
    customChains: [
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=11155111",
          browserURL: "https://sepolia.etherscan.io"
        }
      }
    ]
  },

  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
    only: ['PoolManager'],
  },

  ignition: {
    blockPollingInterval: 10_000,
    requiredConfirmations: 5
  }
};

export default config;
