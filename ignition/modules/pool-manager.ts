

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

// Ignition module to deploy ECM Liquidity Mining Pool system
// Deploys PoolManager, ReferralModule, ReferralVoucher, LiquidityManager, VestingManager, and mock tokens

const ECM_LiquidityMining_Module = buildModule("ECM_LiquidityMining_Module", (m) => {
  // Deploy core contracts
  const poolManager = m.contract("PoolManager", [/* UniswapV2Router address, e.g., mainnet or mock */]);
  const referralModule = m.contract("ReferralModule");
  const referralVoucher = m.contract("ReferralVoucher");
  const liquidityManager = m.contract("LiquidityManager", [/* UniswapV2Router address */, /* treasury address */]);
  const vestingManager = m.contract("VestingManager", [poolManager]);

  // Deploy mock tokens for testing/demo
  const ecmToken = m.contract("MockERC20", ["ECM", "ECM", parseEther("1000000")]);
  const usdtToken = m.contract("MockERC20", ["USDT", "USDT", parseEther("1000000")]);

  // Deploy UniswapV2Pair mock (if needed)
  const uniswapPair = m.contract("MockUniswapV2Pair", [ecmToken, usdtToken]);

  // Wire up contract dependencies
  m.call(poolManager, "setReferralModule", [referralModule]);
  m.call(poolManager, "setReferralVoucher", [referralVoucher]);
  m.call(poolManager, "setVestingManager", [vestingManager]);
  m.call(liquidityManager, "setPoolManager", [poolManager]);
  m.call(referralVoucher, "setPoolManager", [poolManager]);
  m.call(referralModule, "setPoolManager", [poolManager]);

  // Optionally create initial pool (parameters can be customized)
  const createInitialPool = m.getParameter("createInitialPool", false);
  const saleAmount = m.getParameter("saleAmount", parseEther("100000"));
  const rewardAmount = m.getParameter("rewardAmount", parseEther("50000"));
  const liquidityAmount = m.getParameter("liquidityAmount", parseEther("20000"));
  const liquidityUsdtAmount = m.getParameter("liquidityUsdtAmount", parseEther("20000"));
  const allowedStakeDurations = m.getParameter("allowedStakeDurations", [30 * 24 * 3600, 90 * 24 * 3600, 180 * 24 * 3600]);
  const vestingDuration = m.getParameter("vestingDuration", 90 * 24 * 3600);
  const strategy = m.getParameter("strategy", 0); // 0 = LINEAR, 1 = MONTHLY
  const penaltyReceiver = m.getParameter("penaltyReceiver", m.getAccount(0));

  if (createInitialPool) {
    // Approve ECM for sale, rewards, liquidity
    m.call(ecmToken, "approve", [poolManager, saleAmount + rewardAmount + liquidityAmount]);
    m.call(usdtToken, "approve", [poolManager, liquidityUsdtAmount]);

    // Create pool
    m.call(poolManager, "createPool", [
      ecmToken,
      usdtToken,
      uniswapPair,
      penaltyReceiver,
      strategy,
      allowedStakeDurations,
      vestingDuration,
      true // vestRewardsByDefault
    ]);

    // Allocate ECM for sale, rewards, liquidity
    m.call(poolManager, "allocateForSale", [0, saleAmount]);
    m.call(poolManager, "allocateForRewards", [0, rewardAmount]);
    m.call(poolManager, "setLiquidityReserve", [0, liquidityAmount]);
    // Configure reward strategy (example: LINEAR)
    m.call(poolManager, "setLinearRewardRate", [0, parseEther("0.01")]);
    // Activate pool
    m.call(poolManager, "setPoolActive", [0, true]);
  }

  return {
    poolManager,
    referralModule,
    referralVoucher,
    liquidityManager,
    vestingManager,
    ecmToken,
    usdtToken,
    uniswapPair
  };
});

export default ECM_LiquidityMining_Module;