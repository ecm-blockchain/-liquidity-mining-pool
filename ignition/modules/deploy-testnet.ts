import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * ECM Liquidity Mining Pool - TESTNET Deployment (Contracts Only)
 * 
 * This module ONLY deploys the core contracts.
 * Run scripts/wire-contracts.ts afterward to wire up contract dependencies.
 * 
 * Network: ECM Testnet (Chain ID: 1124)
 * RPC: https://rpc.testnet.ecmscan.io
 * 
 * Deployment Order:
 * 1. MockUniswapV2Router (for testnet)
 * 2. PoolManager
 * 3. ReferralModule
 * 4. ReferralVoucher
 * 5. LiquidityManager
 * 6. VestingManager
 */

const ECM_Testnet_Module = buildModule("ECM_Testnet_Module", (m) => {
    // ===================================================================
    // STEP 1: Deploy Mock Uniswap V2 Router (Testnet Only)
    // ===================================================================

    const uniswapRouter = m.contract("MockUniswapV2Router", [], {
        id: "MockUniswapV2Router"
    });

    // ===================================================================
    // STEP 2: Deploy Core Contracts
    // ===================================================================

    // Get treasury address from parameters (defaults to deployer)
    const treasuryAddress = m.getParameter("treasury", m.getAccount(0));

    // Deploy PoolManager with router address
    const poolManager = m.contract("PoolManager", [uniswapRouter], { 
        id: "PoolManager",
        after: [uniswapRouter] 
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

    // Deploy LiquidityManager with router and treasury
    const liquidityManager = m.contract("LiquidityManager", [uniswapRouter, treasuryAddress], {  
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
        vestingManager,
        uniswapRouter
    };
});

export default ECM_Testnet_Module;
