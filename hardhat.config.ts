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

  ignition: {
    requiredConfirmations: 1
  }
};

export default config;
