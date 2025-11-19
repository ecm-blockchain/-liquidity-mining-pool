import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * ECM Liquidity Mining Pool - MAINNET Deployment (Contracts Only)
 * 
 * This module ONLY deploys the core contracts.
 * Run scripts/wire-contracts.ts afterward to wire up contract dependencies.
 * 
 * Network: Ethereum Mainnet (Chain ID: 1)
 * 
 * Pre-deployed Mainnet Addresses:
 * - ECM Token: 0x6f9C25eDc02F21e9df8050a3e67947c99b88f0B2
 * - USDT Token: 0xdAC17F958D2ee523a2206206994597C13D831ec7
 * - ECM/USDT Pair: 0x987ac40d7e3f9305e9dc29bae32b1784b9e7a744
 * - Uniswap V2 Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
 * 
 * ⚠️  MAINNET DEPLOYMENT - PRODUCTION ENVIRONMENT
 * 
 * Pre-deployment Checklist:
 * □ All contracts audited by reputable security firm
 * □ Complete test suite passing (11 test files, 15K+ lines)
 * □ Deployment parameters reviewed and approved
 * □ Multi-sig wallet configured
 * □ Treasury address configured
 * □ Sufficient ETH for deployment gas costs (~5-10 ETH estimated)
 * □ ECM tokens available for initial pool allocation
 * □ Emergency pause mechanism tested
 * □ Monitoring and alerting systems ready
 */

const ECM_Mainnet_Module = buildModule("ECM_Mainnet_Module", (m) => {
  // ===================================================================
  // MAINNET CONFIGURATION
  // ===================================================================
  
  // Uniswap V2 Router on Ethereum Mainnet
  const UNISWAP_ROUTER_ADDRESS = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  
  // Get treasury address from parameters (REQUIRED)
  const treasuryAddress = m.getParameter(
    "treasury",
    m.getAccount(0) // Defaults to deployer
  );
  
  // ===================================================================
  // STEP 1: Deploy Core Contracts
  // ===================================================================
  
  // Deploy PoolManager with mainnet Uniswap V2 Router
  const poolManager = m.contract("PoolManager", [UNISWAP_ROUTER_ADDRESS], {
    id: "PoolManager"
  });
  
  // Deploy ReferralModule
  const referralModule = m.contract("ReferralModule", [], {
    id: "ReferralModule",
    after: [poolManager]
  });
  
  // Deploy ReferralVoucher
  const referralVoucher = m.contract("ReferralVoucher", [], {
    id: "ReferralVoucher",
    after: [referralModule]
  });
  
  // Deploy LiquidityManager with mainnet router and treasury
  const liquidityManager = m.contract("LiquidityManager", [UNISWAP_ROUTER_ADDRESS, treasuryAddress], {
    id: "LiquidityManager",
    after: [poolManager, referralModule, referralVoucher]
  });
  
  // Deploy VestingManager with PoolManager address
  const vestingManager = m.contract("VestingManager", [poolManager], {
    id: "VestingManager",
    after: [poolManager, liquidityManager]
  });

  // ===================================================================
  // RETURN DEPLOYED CONTRACTS
  // ===================================================================
  
  return {
    poolManager,
    referralModule,
    referralVoucher,
    liquidityManager,
    vestingManager
  };
});

export default ECM_Mainnet_Module;
