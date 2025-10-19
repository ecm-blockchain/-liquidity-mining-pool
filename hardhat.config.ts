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
  networks: {
    hardhat: {
      chainId: 1337,
      // forking: {
      //   url: process.env.MAINNET_RPC_URL || "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID",
      //   blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
      // },
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
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
    },
    ecm: {
      url: "https://rpc.testnet.ecmscan.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1124,
    }
  },


  etherscan: {
    enabled: true,
    apiKey: {
      ecm: "abc"
    },
    customChains: [
      {
        network: "ecm",
        chainId: 1124,
        urls: {
          apiURL: "https://explorer.testnet.ecmscan.io/api/v1",
          browserURL: "https://explorer.testnet.ecmscan.io",
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
    requiredConfirmations: 1
  }
};

export default config;
