import { ethers } from "hardhat";
import { parseEther } from "ethers";
import * as fs from "fs";
import * as path from "path";

/**
 * ECM Liquidity Mining Pool - Contract Wiring Script
 * 
 * This script wires up all contract dependencies and optionally creates an initial pool.
 * Run this AFTER deploying contracts with Ignition.
 * 
 * Usage:
 *   npx hardhat run scripts/wire-contracts.ts --network <network-name>
 * 
 * Pre-deployed Testnet Addresses:
 * - ECM Token: 0xA01B74df875441d27a2aDB2a8bE51104D9C65fdb
 * - USDT Token: 0xB6947da0e0d8e0b29E478779bAE3730E8211f563
 * - ECM/USDT Pair: 0x5af70E2F014A77fdA4df2Ebb9C3454280e35a86e
 */

// Configuration
const TESTNET_CONFIG = {
    ECM_TOKEN: "0xA01B74df875441d27a2aDB2a8bE51104D9C65fdb",
    USDT_TOKEN: "0xB6947da0e0d8e0b29E478779bAE3730E8211f563",
    UNISWAP_PAIR: "0x5af70E2F014A77fdA4df2Ebb9C3454280e35a86e"
};

const POOL_CONFIG = {
    saleAmount: parseEther("100000"),      // 100K ECM for sale
    rewardAmount: parseEther("50000"),     // 50K ECM for rewards
    allowedStakeDurations: [
        30 * 24 * 3600,   // 30 days
        90 * 24 * 3600,   // 90 days
        180 * 24 * 3600   // 180 days
    ],
    maxDuration: 180 * 24 * 3600,          // 180 days
    vestingDuration: 90 * 24 * 3600,       // 90 days vesting
    strategy: 0,                           // 0 = LINEAR, 1 = MONTHLY, 2 = WEEKLY
    vestRewardsByDefault: false,
    penaltyBps: 2500                       // 25% penalty for early unstaking
};

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("\n🔧 Starting contract wiring process...");
    console.log(`   Deployer: ${deployer.address}`);
    console.log(`   Network: ${(await ethers.provider.getNetwork()).name}`);
    
    // ===================================================================
    // STEP 1: Load Deployed Contract Addresses from Ignition
    // ===================================================================
    
    console.log("\n📋 Loading deployed contract addresses from Ignition...");
    
    const deploymentPath = path.join(
        __dirname,
        "..",
        "ignition",
        "deployments",
        "deployment-v1",
        "deployed_addresses.json"
    );
    
    if (!fs.existsSync(deploymentPath)) {
        throw new Error(
            `Deployment file not found at: ${deploymentPath}\n` +
            `Please run deployment first: npm run deploy:testnet`
        );
    }
    
    const deployedAddresses = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
    
    const addresses = {
        poolManager: deployedAddresses["ECM_Testnet_Module#PoolManager"],
        referralModule: deployedAddresses["ECM_Testnet_Module#ReferralModule"],
        referralVoucher: deployedAddresses["ECM_Testnet_Module#ReferralVoucher"],
        liquidityManager: deployedAddresses["ECM_Testnet_Module#LiquidityManager"],
        vestingManager: deployedAddresses["ECM_Testnet_Module#VestingManager"],
        uniswapRouter: deployedAddresses["ECM_Testnet_Module#MockUniswapV2Router"]
    };
    
    console.log("   ✅ Contract addresses loaded:");
    console.log(`      PoolManager: ${addresses.poolManager}`);
    console.log(`      ReferralModule: ${addresses.referralModule}`);
    console.log(`      ReferralVoucher: ${addresses.referralVoucher}`);
    console.log(`      LiquidityManager: ${addresses.liquidityManager}`);
    console.log(`      VestingManager: ${addresses.vestingManager}`);
    console.log(`      UniswapRouter: ${addresses.uniswapRouter}`);
    
    // ===================================================================
    // STEP 2: Get Contract Instances
    // ===================================================================
    
    console.log("\n🔗 Connecting to deployed contracts...");
    
    const poolManager = await ethers.getContractAt("PoolManager", addresses.poolManager);
    const referralModule = await ethers.getContractAt("ReferralModule", addresses.referralModule);
    const referralVoucher = await ethers.getContractAt("ReferralVoucher", addresses.referralVoucher);
    const liquidityManager = await ethers.getContractAt("LiquidityManager", addresses.liquidityManager);
    const vestingManager = await ethers.getContractAt("VestingManager", addresses.vestingManager);
    
    console.log("   ✅ Connected to all contracts");
    
    // ===================================================================
    // STEP 3: Wire Up Contract Dependencies
    // ===================================================================
    
    console.log("\n🔌 Wiring up contract dependencies...");
    
    // 3.1: Set integrations in PoolManager
    console.log("\n   Setting PoolManager integrations...");
    
    let tx = await poolManager.setReferralModule(addresses.referralModule);
    await tx.wait();
    console.log("      ✅ setReferralModule");
    
    tx = await poolManager.setReferralVoucher(addresses.referralVoucher);
    await tx.wait();
    console.log("      ✅ setReferralVoucher");
    
    tx = await poolManager.setVestingManager(addresses.vestingManager);
    await tx.wait();
    console.log("      ✅ setVestingManager");
    
    tx = await poolManager.addAuthorizedLiquidityManager(addresses.liquidityManager);
    await tx.wait();
    console.log("      ✅ addAuthorizedLiquidityManager");
    
    // 3.2: Set PoolManager in dependent contracts
    console.log("\n   Setting PoolManager in dependent contracts...");
    
    tx = await liquidityManager.setPoolManager(addresses.poolManager);
    await tx.wait();
    console.log("      ✅ LiquidityManager.setPoolManager");
    
    tx = await referralVoucher.setPoolManager(addresses.poolManager);
    await tx.wait();
    console.log("      ✅ ReferralVoucher.setPoolManager");
    
    tx = await referralModule.setPoolManager(addresses.poolManager);
    await tx.wait();
    console.log("      ✅ ReferralModule.setPoolManager");
    
    // 3.3: Authorize PoolManager in VestingManager
    console.log("\n   Authorizing PoolManager in VestingManager...");
    
    tx = await vestingManager.addAuthorizedCreator(addresses.poolManager);
    await tx.wait();
    console.log("      ✅ VestingManager.addAuthorizedCreator");
    
    console.log("\n✅ All contract dependencies wired successfully!");
    
    // ===================================================================
    // STEP 4: Optional Initial Pool Creation
    // ===================================================================
    
    console.log("\n🏊 Creating initial pool...");
    
    // 4.1: Get ECM token contract instance
    const ecmToken = await ethers.getContractAt("MockERC20", TESTNET_CONFIG.ECM_TOKEN);
    
    // 4.2: Check current allowance and balance
    const currentAllowance = await ecmToken.allowance(deployer.address, addresses.poolManager);
    const deployerBalance = await ecmToken.balanceOf(deployer.address);
    const totalRequired = POOL_CONFIG.saleAmount + POOL_CONFIG.rewardAmount;
    
    console.log(`\n   Deployer ECM Balance: ${ethers.formatEther(deployerBalance)} ECM`);
    console.log(`   Total Required: ${ethers.formatEther(totalRequired)} ECM (150K)`);
    console.log(`   Current Allowance: ${ethers.formatEther(currentAllowance)} ECM`);
    
    if (deployerBalance < totalRequired) {
        console.warn(`\n   ⚠️  WARNING: Insufficient ECM balance!`);
        console.warn(`      You need ${ethers.formatEther(totalRequired)} ECM but only have ${ethers.formatEther(deployerBalance)} ECM`);
        console.warn(`      Skipping pool creation. Please fund your wallet and run this script again.`);
        return;
    }
    
    // 4.3: Approve ECM tokens if needed
    if (currentAllowance < totalRequired) {
        console.log(`\n   Approving ${ethers.formatEther(totalRequired)} ECM for PoolManager...`);
        tx = await ecmToken.approve(addresses.poolManager, totalRequired);
        await tx.wait();
        console.log("      ✅ ECM tokens approved");
    } else {
        console.log("      ✅ Sufficient approval already exists");
    }
    
    // 4.4: Create pool
    console.log("\n   Creating pool with configuration...");
    console.log(`      Sale Amount: ${ethers.formatEther(POOL_CONFIG.saleAmount)} ECM`);
    console.log(`      Reward Amount: ${ethers.formatEther(POOL_CONFIG.rewardAmount)} ECM`);
    console.log(`      Strategy: ${POOL_CONFIG.strategy === 0 ? "LINEAR" : POOL_CONFIG.strategy === 1 ? "MONTHLY" : "WEEKLY"}`);
    console.log(`      Penalty: ${POOL_CONFIG.penaltyBps / 100}%`);
    console.log(`      Allowed Durations: ${POOL_CONFIG.allowedStakeDurations.map(d => `${d / (24 * 3600)} days`).join(", ")}`);
    
    const poolParams = {
        ecm: TESTNET_CONFIG.ECM_TOKEN,
        usdt: TESTNET_CONFIG.USDT_TOKEN,
        pair: TESTNET_CONFIG.UNISWAP_PAIR,
        penaltyReceiver: deployer.address,
        rewardStrategy: POOL_CONFIG.strategy,
        allowedStakeDurations: POOL_CONFIG.allowedStakeDurations,
        maxDuration: POOL_CONFIG.maxDuration,
        vestingDuration: POOL_CONFIG.vestingDuration,
        vestRewardsByDefault: POOL_CONFIG.vestRewardsByDefault,
        penaltyBps: POOL_CONFIG.penaltyBps
    };
    
    tx = await poolManager.createPool(poolParams);
    await tx.wait();
    console.log("      ✅ Pool created (Pool ID: 0)");
    
    // 4.5: Allocate ECM for sale
    console.log("\n   Allocating ECM tokens...");
    
    tx = await poolManager.allocateForSale(0, POOL_CONFIG.saleAmount);
    await tx.wait();
    console.log(`      ✅ Allocated ${ethers.formatEther(POOL_CONFIG.saleAmount)} ECM for sale`);
    
    // 4.6: Allocate ECM for rewards
    tx = await poolManager.allocateForRewards(0, POOL_CONFIG.rewardAmount);
    await tx.wait();
    console.log(`      ✅ Allocated ${ethers.formatEther(POOL_CONFIG.rewardAmount)} ECM for rewards`);
    
    // 4.7: Set reward rate for LINEAR strategy
    if (POOL_CONFIG.strategy === 0) {
        console.log("\n   Setting LINEAR reward rate...");
        tx = await poolManager.setLinearRewardRate(0);
        await tx.wait();
        console.log("      ✅ LINEAR reward rate set");
    } else if (POOL_CONFIG.strategy === 1) {
        console.log("\n   ⚠️  MONTHLY strategy detected - you need to manually call setMonthlyRewards()");
    } else if (POOL_CONFIG.strategy === 2) {
        console.log("\n   ⚠️  WEEKLY strategy detected - you need to manually call setWeeklyRewards()");
    }
    
    // 4.8: Activate pool
    console.log("\n   Activating pool...");
    tx = await poolManager.setPoolActive(0, true);
    await tx.wait();
    console.log("      ✅ Pool activated");
    
    // ===================================================================
    // STEP 5: Verification Summary
    // ===================================================================
    
    console.log("\n" + "=".repeat(70));
    console.log("✅ CONTRACT WIRING COMPLETE!");
    console.log("=".repeat(70));
    console.log("\n📊 Deployment Summary:");
    console.log("\n   Core Contracts:");
    console.log(`      PoolManager: ${addresses.poolManager}`);
    console.log(`      ReferralModule: ${addresses.referralModule}`);
    console.log(`      ReferralVoucher: ${addresses.referralVoucher}`);
    console.log(`      LiquidityManager: ${addresses.liquidityManager}`);
    console.log(`      VestingManager: ${addresses.vestingManager}`);
    console.log(`      UniswapRouter: ${addresses.uniswapRouter}`);
    
    console.log("\n   Pool Configuration:");
    console.log(`      Pool ID: 0`);
    console.log(`      Status: ACTIVE ✅`);
    console.log(`      Sale Allocation: ${ethers.formatEther(POOL_CONFIG.saleAmount)} ECM`);
    console.log(`      Reward Allocation: ${ethers.formatEther(POOL_CONFIG.rewardAmount)} ECM`);
    console.log(`      Strategy: ${POOL_CONFIG.strategy === 0 ? "LINEAR" : POOL_CONFIG.strategy === 1 ? "MONTHLY" : "WEEKLY"}`);
    console.log(`      Early Unstake Penalty: ${POOL_CONFIG.penaltyBps / 100}%`);
    
    console.log("\n   Token Addresses:");
    console.log(`      ECM Token: ${TESTNET_CONFIG.ECM_TOKEN}`);
    console.log(`      USDT Token: ${TESTNET_CONFIG.USDT_TOKEN}`);
    console.log(`      ECM/USDT Pair: ${TESTNET_CONFIG.UNISWAP_PAIR}`);
    
    console.log("\n🎉 Your ECM Liquidity Mining Pool is ready for users!");
    console.log("=".repeat(70) + "\n");
    
    // Save wiring summary to file
    const net = await ethers.provider.getNetwork();
    const wiringSummary = {
        timestamp: new Date().toISOString(),
        network: net.name,
        chainId: Number(net.chainId),
        deployer: deployer.address,
        contracts: addresses,
        tokens: TESTNET_CONFIG,
        poolConfig: {
            poolId: 0,
            status: "ACTIVE",
            saleAmount: ethers.formatEther(POOL_CONFIG.saleAmount),
            rewardAmount: ethers.formatEther(POOL_CONFIG.rewardAmount),
            strategy: POOL_CONFIG.strategy === 0 ? "LINEAR" : POOL_CONFIG.strategy === 1 ? "MONTHLY" : "WEEKLY",
            penaltyBps: POOL_CONFIG.penaltyBps,
            allowedStakeDurations: POOL_CONFIG.allowedStakeDurations.map(d => `${d / (24 * 3600)} days`)
        }
    };
    
    const summaryPath = path.join(__dirname, "..", "deployment-summary.json");
    fs.writeFileSync(
        summaryPath,
        JSON.stringify(
            wiringSummary,
            (_key, value) => (typeof value === "bigint" ? value.toString() : value),
            2
        )
    );
    console.log(`📄 Deployment summary saved to: ${summaryPath}\n`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n❌ Error during contract wiring:");
        console.error(error);
        process.exit(1);
    });
