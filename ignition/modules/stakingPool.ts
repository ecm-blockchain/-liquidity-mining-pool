
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

// Ignition module to deploy StakingPool.
// Optionally deploys mock ERC20 tokens and creates an initial pool when enabled via parameters.
// Parameters (override with --parameters when running ignition):
// - createInitialPool: boolean (default: false)
// - startTime: number (unix seconds) - required if createInitialPool = true
// - endTime: number (unix seconds) - required if createInitialPool = true
// - precision: number (default: 18)
// - totalReward: string (wei, default: 100000 ether)

const StakingPool_Module = buildModule("StakingPool_Module", (m) => {
  // Deploy core contract (owner will be the deployer)
  const stakingPool = m.contract("StakingPool");

  // Always deploy simple mock tokens for convenience. Consumers can ignore these
  // and use their own tokens by calling addPool manually after deployment.
  const stakingToken = m.contract("MockERC20", ["Stake", "STK", parseEther("1000000")]);
  const rewardToken = m.contract("MockERC20", ["Reward", "RWD", parseEther("1000000")]);

  // Configurable parameters for optional initial pool creation
  const createInitialPool = m.getParameter("createInitialPool", false);
  const precision = m.getParameter("precision", 18);
  const totalReward = m.getParameter("totalReward", parseEther("100000"));
  const startTime = m.getParameter("startTime", 0);
  const endTime = m.getParameter("endTime", 0);

  // Optionally set up an initial pool if parameters are provided
  if (createInitialPool) {
    // Approve StakingPool to pull reward tokens from deployer when creating the pool
    m.call(rewardToken, "approve", [stakingPool, totalReward]);
    m.call(stakingPool, "addPool", [
      stakingToken,
      rewardToken,
      startTime,
      endTime,
      precision,
      totalReward,
    ]);
  }

  return { stakingPool, stakingToken, rewardToken };
});

export default StakingPool_Module;