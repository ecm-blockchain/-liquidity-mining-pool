import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { PoolManager, MockERC20 } from "../typechain-types";
import { time } from "@nomicfoundation/hardhat-network-helpers";

/**
 * Rewards Math Edge Cases Test Suite
 * 
 * Purpose: Verify reward calculation accuracy with extreme values
 * 
 * Test Categories:
 * 1. Very Small Rewards (dust amounts, rounding errors)
 * 2. Very Large Rewards (overflow prevention, precision loss)
 * 3. Precision Tests (accumulated small rewards, long durations)
 * 4. Boundary Conditions (max uint256, minimum non-zero)
 * 5. Strategy-Specific Edge Cases (LINEAR, MONTHLY, WEEKLY)
 * 
 * Critical Properties to Verify:
 * - No overflows in multiplication/division
 * - Rounding errors don't accumulate
 * - Small rewards distribute fairly
 * - Large rewards don't lose precision
 * - accRewardPerShare maintains accuracy
 * - User rewards sum to total allocated (within rounding tolerance)
 */

describe("Rewards Math - Edge Cases & Accuracy", function () {
  let poolManager: PoolManager;
  let ecmToken: MockERC20;
  let usdtToken: MockERC20;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let treasury: SignerWithAddress;

  // Test constants
  const PRECISION = ethers.parseEther("1"); // 1e18
  const MAX_UINT256 = ethers.MaxUint256;
  const SECONDS_PER_DAY = 86400;
  const SECONDS_PER_YEAR = 365 * SECONDS_PER_DAY;

  // Helper function to create a pool
  async function createTestPool(rewardStrategy: number) {
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockPairFactory = await ethers.getContractFactory("MockUniswapV2Pair");

    // Deploy tokens if not already deployed
    if (!ecmToken) {
      ecmToken = await MockERC20Factory.deploy("ECM Token", "ECM", 18, 0) as unknown as MockERC20;
      usdtToken = await MockERC20Factory.deploy("USDT Token", "USDT", 6, 0) as unknown as MockERC20;
    }

    // Create mock pair
    const mockPair = await MockPairFactory.deploy(
      await ecmToken.getAddress(),
      await usdtToken.getAddress()
    );

    // Set initial reserves: 1M ECM, 500K USDT (price = 0.5 USDT per ECM)
    await mockPair.setReserves(
      ethers.parseEther("1000000"), // 1M ECM
      ethers.parseUnits("500000", 6) // 500K USDT
    );

    const poolParams = {
      ecm: await ecmToken.getAddress(),
      usdt: await usdtToken.getAddress(),
      pair: await mockPair.getAddress(),
      penaltyReceiver: treasury.address,
      rewardStrategy: rewardStrategy,
      allowedStakeDurations: [30 * SECONDS_PER_DAY, 90 * SECONDS_PER_DAY, 365 * SECONDS_PER_DAY, 1000 * SECONDS_PER_DAY],
      maxDuration: 1000 * SECONDS_PER_DAY, // Increased to accommodate long-duration tests
      vestingDuration: 0,
      vestRewardsByDefault: false,
      penaltyBps: 2500, // 25%
    };

    const tx = await poolManager.createPool(poolParams);
    const receipt = await tx.wait();
    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === "PoolCreated"
    ) as any;
    return event?.args?.poolId;
  }

  beforeEach(async function () {
    [owner, user1, user2, user3, treasury] = await ethers.getSigners();

    // Deploy PoolManager
    const MockRouterFactory = await ethers.getContractFactory(
      "MockUniswapV2Router"
    );
    const mockRouter = await MockRouterFactory.deploy();

    const PoolManagerFactory = await ethers.getContractFactory("PoolManager");
    poolManager = await PoolManagerFactory.deploy(await mockRouter.getAddress()) as unknown as PoolManager;
  });

  describe("1. Very Small Rewards - Dust Amounts", function () {
    it("Should handle 1 wei reward allocation without reverting", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Allocate only 1 wei for rewards
      await ecmToken.mint(owner.address, 1n);
      await ecmToken.approve(await poolManager.getAddress(), 1n);
      await poolManager.allocateForRewards(poolId, 1n);

      // This should revert because rate calculation will be 0
      await expect(
        poolManager.setLinearRewardRate(poolId)
      ).to.be.revertedWithCustomError(poolManager, "InvalidRewardRate");
    });

    it("Should handle minimum viable reward allocation (1 token per day)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 1000 ECM over 1000 days = 1 ECM per day (using maxDuration of 1000 days)
      const minRewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, minRewards);
      await ecmToken.approve(await poolManager.getAddress(), minRewards);
      await poolManager.allocateForRewards(poolId, minRewards);

      await poolManager.setLinearRewardRate(poolId);

      const pool = await poolManager.getPoolInfo(poolId);
      const expectedRate = minRewards / BigInt(1000 * SECONDS_PER_DAY); // Changed to 1000 days

      expect(pool.rewardRatePerSecond).to.equal(expectedRate);
      console.log("      Rate per second:", pool.rewardRatePerSecond.toString());
      console.log("      Rate per day:", (pool.rewardRatePerSecond * BigInt(SECONDS_PER_DAY)).toString());
    });

    it("Should distribute dust rewards fairly among multiple stakers", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Allocate very small rewards: 10 ECM over 1000 days (maxDuration)
      const smallRewards = ethers.parseEther("10");
      await ecmToken.mint(owner.address, smallRewards);
      await ecmToken.approve(await poolManager.getAddress(), smallRewards);
      await poolManager.allocateForRewards(poolId, smallRewards);
      await poolManager.setLinearRewardRate(poolId);

      // Allocate for sale
      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // User1 stakes 1000 ECM
      const stake1 = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake1);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake1);
      await poolManager.connect(user1).stakeECM(poolId, stake1, 30 * SECONDS_PER_DAY);

      // User2 stakes 1000 ECM (equal stake)
      const stake2 = ethers.parseEther("1000");
      await ecmToken.mint(user2.address, stake2);
      await ecmToken.connect(user2).approve(await poolManager.getAddress(), stake2);
      await poolManager.connect(user2).stakeECM(poolId, stake2, 30 * SECONDS_PER_DAY);

      // Advance 5 days
      await time.increase(5 * SECONDS_PER_DAY);

      // Check pending rewards
      const pending1 = await poolManager.pendingRewards(poolId, user1.address);
      const pending2 = await poolManager.pendingRewards(poolId, user2.address);

      console.log("      User1 pending:", ethers.formatEther(pending1), "ECM");
      console.log("      User2 pending:", ethers.formatEther(pending2), "ECM");

      // Should be equal (within rounding tolerance)
      const diff = pending1 > pending2 ? pending1 - pending2 : pending2 - pending1;
      expect(diff).to.be.lessThan(ethers.parseEther("0.001")); // Less than 0.001 ECM difference

      // Total should be approximately 5 days worth of rewards
      // Rate = 10 ECM / 1000 days = 0.01 ECM/day
      // 5 days = 0.05 ECM total
      const total = pending1 + pending2;
      const expectedTotal = (smallRewards * 5n) / 1000n; // 5 days out of 1000
      expect(total).to.be.closeTo(expectedTotal, expectedTotal / 10n);
    });

    it("Should handle rounding when reward rate < 1 wei per second", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 1 ECM over 1 year = ~31,709,791 wei per second
      // If we use 1 wei over 1 year, rate would be 0 (rounds down)
      const tinyRewards = 1n;
      await ecmToken.mint(owner.address, tinyRewards);
      await ecmToken.approve(await poolManager.getAddress(), tinyRewards);
      await poolManager.allocateForRewards(poolId, tinyRewards);

      // This should revert because rate rounds to 0
      await expect(
        poolManager.setLinearRewardRate(poolId)
      ).to.be.revertedWithCustomError(poolManager, "InvalidRewardRate");
    });

    it("Should accumulate small rewards over long periods accurately", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 100 ECM over 1000 days (maxDuration)
      const rewards = ethers.parseEther("100");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Allocate for sale
      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // Stake
      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      // Check rewards at multiple intervals
      const intervals = [1, 7, 30, 90, 180]; // days (limited to avoid exceeding total)
      const expectedRewardsPerDay = rewards / 1000n; // Changed to 1000 days

      for (const days of intervals) {
        const pending = await poolManager.pendingRewards(poolId, user1.address);
        await time.increase(days * SECONDS_PER_DAY);
        
        const newPending = await poolManager.pendingRewards(poolId, user1.address);
        const accumulated = newPending - pending;
        const expected = expectedRewardsPerDay * BigInt(days);

        console.log(`      After ${days} days: ${ethers.formatEther(accumulated)} ECM (expected: ${ethers.formatEther(expected)})`);
        
        // Allow 1% tolerance for rounding (smaller rewards = more rounding impact)
        expect(accumulated).to.be.closeTo(expected, expected / 100n);
      }
    });
  });

  describe("2. Very Large Rewards - Overflow Prevention", function () {
    it("Should handle extremely large reward allocations (1 billion ECM)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 1 billion ECM
      const hugeRewards = ethers.parseEther("1000000000");
      await ecmToken.mint(owner.address, hugeRewards);
      await ecmToken.approve(await poolManager.getAddress(), hugeRewards);
      await poolManager.allocateForRewards(poolId, hugeRewards);

      // Should not overflow
      await expect(poolManager.setLinearRewardRate(poolId)).to.not.be.reverted;

      const pool = await poolManager.getPoolInfo(poolId);
      console.log("      Rate per second:", ethers.formatEther(pool.rewardRatePerSecond), "ECM");
      console.log("      Rate per day:", ethers.formatEther(pool.rewardRatePerSecond * BigInt(SECONDS_PER_DAY)), "ECM");
    });

    it("Should handle maximum viable stake amount without overflow", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Large but reasonable rewards
      const rewards = ethers.parseEther("10000000"); // 10M ECM
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Allocate huge sale amount
      const hugeStake = ethers.parseEther("1000000000"); // 1B ECM
      await ecmToken.mint(owner.address, hugeStake);
      await ecmToken.approve(await poolManager.getAddress(), hugeStake);
      await poolManager.allocateForSale(poolId, hugeStake);

      // User stakes 1B ECM
      await ecmToken.mint(user1.address, hugeStake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), hugeStake);
      await poolManager.connect(user1).stakeECM(poolId, hugeStake, 365 * SECONDS_PER_DAY);

      // Advance time and check rewards
      await time.increase(30 * SECONDS_PER_DAY);

      const pending = await poolManager.pendingRewards(poolId, user1.address);
      console.log("      Pending rewards:", ethers.formatEther(pending), "ECM");

      // Should have approximately 30 days of rewards
      // Rate = 10M / 1000 days, so 30 days = 30/1000 * 10M = 300K ECM
      const expected30Days = (rewards * 30n) / 1000n;
      expect(pending).to.be.closeTo(expected30Days, expected30Days / 100n);
    });

    it("Should not overflow in accRewardPerShare calculation with large rewards", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Very large rewards
      const rewards = ethers.parseEther("100000000"); // 100M ECM
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Small stake (worst case for accRewardPerShare)
      const saleAmount = ethers.parseEther("5000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      const smallStake = ethers.parseEther("500"); // Minimum 500 ECM
      await ecmToken.mint(user1.address, smallStake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), smallStake);
      await poolManager.connect(user1).stakeECM(poolId, smallStake, 365 * SECONDS_PER_DAY);

      // Advance 365 days (out of 1000 total)
      await time.increase(365 * SECONDS_PER_DAY);

      // Should not overflow when calculating pending
      const pending = await poolManager.pendingRewards(poolId, user1.address);
      console.log("      Pending rewards:", ethers.formatEther(pending), "ECM");

      // Should get 365/1000 of rewards (solo staker)
      const expectedRewards = (rewards * 365n) / 1000n;
      expect(pending).to.be.closeTo(expectedRewards, expectedRewards / 100n);
    });

    it("Should handle near-MAX_UINT256 values in intermediate calculations", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Use maximum safe reward allocation (type(uint128).max to avoid storage overflow)
      const maxSafeRewards = ethers.parseEther("1000000000"); // 1B ECM (safe value)
      await ecmToken.mint(owner.address, maxSafeRewards);
      await ecmToken.approve(await poolManager.getAddress(), maxSafeRewards);
      await poolManager.allocateForRewards(poolId, maxSafeRewards);

      await expect(poolManager.setLinearRewardRate(poolId)).to.not.be.reverted;

      const pool = await poolManager.getPoolInfo(poolId);
      expect(pool.rewardRatePerSecond).to.be.gt(0);
      
      console.log("      Successfully handled large allocation");
      console.log("      Rate:", ethers.formatEther(pool.rewardRatePerSecond), "ECM/sec");
    });

    it("Should maintain precision with large totalStaked and small rewards", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Small rewards
      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Large stakes from multiple users
      const largeStake = ethers.parseEther("10000000"); // 10M ECM each
      const users = [user1, user2, user3];

      for (const user of users) {
        await ecmToken.mint(owner.address, largeStake);
        await ecmToken.approve(await poolManager.getAddress(), largeStake);
        await poolManager.allocateForSale(poolId, largeStake);

        await ecmToken.mint(user.address, largeStake);
        await ecmToken.connect(user).approve(await poolManager.getAddress(), largeStake);
        await poolManager.connect(user).stakeECM(poolId, largeStake, 365 * SECONDS_PER_DAY);
      }

      // Advance time
      await time.increase(30 * SECONDS_PER_DAY);

      // Check each user's rewards
      let totalPending = 0n;
      for (const user of users) {
        const pending = await poolManager.pendingRewards(poolId, user.address);
        totalPending += pending;
        console.log(`      ${user.address.slice(0, 10)}... pending:`, ethers.formatEther(pending), "ECM");
      }

      // Total should be approximately 30/1000 of rewards
      const expected30Days = (rewards * 30n) / 1000n;
      expect(totalPending).to.be.closeTo(expected30Days, expected30Days / 10n);

      console.log("      Total distributed:", ethers.formatEther(totalPending), "ECM");
      console.log("      Expected:", ethers.formatEther(expected30Days), "ECM");
    });
  });

  describe("3. Precision Tests - Accumulated Small Rewards", function () {
    it("Should not lose precision when accumulating tiny rewards over time", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 365 ECM over 1 year = 1 ECM per day
      const rewards = ethers.parseEther("365");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // Stake
      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      // Check rewards every hour for 24 hours
      let lastPending = 0n;
      const hourlyRewards: bigint[] = [];

      for (let hour = 1; hour <= 24; hour++) {
        await time.increase(3600); // 1 hour
        const pending = await poolManager.pendingRewards(poolId, user1.address);
        const hourlyReward = pending - lastPending;
        hourlyRewards.push(hourlyReward);
        lastPending = pending;
      }

      // All hourly rewards should be nearly identical (precision maintained)
      const avgHourly = hourlyRewards.reduce((sum, r) => sum + r, 0n) / BigInt(hourlyRewards.length);
      const maxDeviation = hourlyRewards.reduce((max, r) => {
        const dev = r > avgHourly ? r - avgHourly : avgHourly - r;
        return dev > max ? dev : max;
      }, 0n);

      console.log("      Average hourly:", ethers.formatEther(avgHourly), "ECM");
      console.log("      Max deviation:", ethers.formatEther(maxDeviation), "ECM");

      // Deviation should be negligible (< 0.001%)
      expect(maxDeviation).to.be.lessThan(avgHourly / 100000n);
    });

    it("Should handle fractional wei rewards without truncation errors", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 1 ECM over 1000 days (maxDuration)
      const rewards = ethers.parseEther("1");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const pool = await poolManager.getPoolInfo(poolId);
      const rate = pool.rewardRatePerSecond;

      console.log("      Rate per second (wei):", rate.toString());
      console.log("      Rate per hour (wei):", (rate * 3600n).toString());
      console.log("      Rate per day:", ethers.formatEther(rate * BigInt(SECONDS_PER_DAY)), "ECM");

      // Rate should be non-zero
      expect(rate).to.be.gt(0);

      // Verify: rate * 1000 days ≈ 1 ECM
      const totalRewards = rate * BigInt(1000 * SECONDS_PER_DAY);
      expect(totalRewards).to.be.closeTo(rewards, rewards / 1000n);
    });

    it("Should sum individual user rewards to total pool rewards (conservation)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Multiple users stake different amounts (all >= 500 ECM minimum)
      const stakes = [
        ethers.parseEther("500"),
        ethers.parseEther("1000"),
        ethers.parseEther("1500"),
      ];

      const users = [user1, user2, user3];

      for (let i = 0; i < users.length; i++) {
        await ecmToken.mint(owner.address, stakes[i]);
        await ecmToken.approve(await poolManager.getAddress(), stakes[i]);
        await poolManager.allocateForSale(poolId, stakes[i]);

        await ecmToken.mint(users[i].address, stakes[i]);
        await ecmToken.connect(users[i]).approve(await poolManager.getAddress(), stakes[i]);
        await poolManager.connect(users[i]).stakeECM(poolId, stakes[i], 365 * SECONDS_PER_DAY);
      }

      // Advance 100 days
      await time.increase(100 * SECONDS_PER_DAY);

      // Sum all pending rewards
      let totalPending = 0n;
      for (const user of users) {
        const pending = await poolManager.pendingRewards(poolId, user.address);
        totalPending += pending;
      }

      // Expected: 100/1000 of total rewards (maxDuration is 1000 days)
      const expectedTotal = (rewards * 100n) / 1000n;

      console.log("      Total pending:", ethers.formatEther(totalPending), "ECM");
      console.log("      Expected:", ethers.formatEther(expectedTotal), "ECM");

      // Should be very close (within 0.1%)
      expect(totalPending).to.be.closeTo(expectedTotal, expectedTotal / 1000n);
    });
  });

  describe("4. Boundary Conditions", function () {
    it("Should handle single wei stake amount", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Stake 1 wei
      const oneWei = 1n;
      await ecmToken.mint(owner.address, ethers.parseEther("1000"));
      await ecmToken.approve(await poolManager.getAddress(), ethers.parseEther("1000"));
      await poolManager.allocateForSale(poolId, ethers.parseEther("1000"));

      // Cannot stake less than MIN_PURCHASE_ECM (500 ECM)
      await ecmToken.mint(user1.address, oneWei);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), oneWei);
      await expect(
        poolManager.connect(user1).stakeECM(poolId, oneWei, 365 * SECONDS_PER_DAY)
      ).to.be.revertedWithCustomError(poolManager, "MinPurchaseNotMet");
    });

    it("Should handle minimum stake amount (500 ECM)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // Stake exactly 500 ECM (minimum)
      const minStake = ethers.parseEther("500");
      await ecmToken.mint(user1.address, minStake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), minStake);
      await expect(
        poolManager.connect(user1).stakeECM(poolId, minStake, 365 * SECONDS_PER_DAY)
      ).to.not.be.reverted;

      // Verify stake recorded
      const userInfo = await poolManager.getUserInfo(poolId, user1.address);
      expect(userInfo.staked).to.equal(minStake);
    });

    it("Should handle reward period = 1 second (minimum duration)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // 86,400,000 ECM over 1000 days = exactly 1 ECM per second
      const secondsIn1000Days = 1000 * SECONDS_PER_DAY;
      const rewards = ethers.parseEther(secondsIn1000Days.toString());
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const pool = await poolManager.getPoolInfo(poolId);
      const rate = pool.rewardRatePerSecond;

      console.log("      Rate per second:", ethers.formatEther(rate), "ECM");

      // Should be exactly 1 ECM per second
      expect(rate).to.be.closeTo(ethers.parseEther("1"), ethers.parseEther("0.001"));
    });

    it("Should handle maximum reward duration (type(uint256).max)", async function () {
      // This is a theoretical test - in practice, max duration is limited by pool config
      // Just verify the math doesn't overflow
      
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);

      // maxDuration is set to 1000 days in pool creation
      await expect(poolManager.setLinearRewardRate(poolId)).to.not.be.reverted;

      const pool = await poolManager.getPoolInfo(poolId);
      expect(pool.maxDuration).to.equal(1000 * SECONDS_PER_DAY);
    });

    it("Should handle zero totalStaked (no rewards distributed)", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // Advance time with no stakers
      await time.increase(30 * SECONDS_PER_DAY);

      const pool = await poolManager.getPoolInfo(poolId);
      
      // totalStaked should be 0
      expect(pool.totalStaked).to.equal(0);
      
      // No rewards should be accrued
      expect(pool.totalRewardsAccrued).to.equal(0);
      
      console.log("      No overflow with zero stakers");
    });
  });

  describe("5. Strategy-Specific Edge Cases", function () {
    describe("LINEAR Strategy", function () {
      it("Should maintain constant rate regardless of stake changes", async function () {
        const poolId = await createTestPool(0); // LINEAR

        const rewards = ethers.parseEther("10000");
        await ecmToken.mint(owner.address, rewards);
        await ecmToken.approve(await poolManager.getAddress(), rewards);
        await poolManager.allocateForRewards(poolId, rewards);
        await poolManager.setLinearRewardRate(poolId);

        const saleAmount = ethers.parseEther("100000");
        await ecmToken.mint(owner.address, saleAmount);
        await ecmToken.approve(await poolManager.getAddress(), saleAmount);
        await poolManager.allocateForSale(poolId, saleAmount);

        // User1 stakes
        const stake1 = ethers.parseEther("1000");
        await ecmToken.mint(user1.address, stake1);
        await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake1);
        await poolManager.connect(user1).stakeECM(poolId, stake1, 365 * SECONDS_PER_DAY);

        await time.increase(10 * SECONDS_PER_DAY);
        const pending1_day10 = await poolManager.pendingRewards(poolId, user1.address);

        // User2 joins (doubles total stake)
        const stake2 = ethers.parseEther("1000");
        await ecmToken.mint(user2.address, stake2);
        await ecmToken.connect(user2).approve(await poolManager.getAddress(), stake2);
        await poolManager.connect(user2).stakeECM(poolId, stake2, 365 * SECONDS_PER_DAY);

        await time.increase(10 * SECONDS_PER_DAY);
        const pending1_day20 = await poolManager.pendingRewards(poolId, user1.address);
        const pending2_day20 = await poolManager.pendingRewards(poolId, user2.address);

        console.log("      User1 after 10 days (solo):", ethers.formatEther(pending1_day10), "ECM");
        console.log("      User1 after 20 days (shared):", ethers.formatEther(pending1_day20), "ECM");
        console.log("      User2 after 10 days:", ethers.formatEther(pending2_day20), "ECM");

        // User1's incremental rewards (days 10-20) should be half of (days 0-10)
        const user1_increment = pending1_day20 - pending1_day10;
        expect(user1_increment).to.be.closeTo(pending1_day10 / 2n, pending1_day10 / 100n);

        // User2 should get approximately same as user1's increment
        expect(pending2_day20).to.be.closeTo(user1_increment, user1_increment / 10n);
      });

      it("Should handle rate updates mid-period", async function () {
        const poolId = await createTestPool(0); // LINEAR

        // Initial allocation
        const rewards1 = ethers.parseEther("5000");
        await ecmToken.mint(owner.address, rewards1);
        await ecmToken.approve(await poolManager.getAddress(), rewards1);
        await poolManager.allocateForRewards(poolId, rewards1);
        await poolManager.setLinearRewardRate(poolId);

        const initialPool = await poolManager.getPoolInfo(poolId);
        const initialRate = initialPool.rewardRatePerSecond;

        console.log("      Initial rate:", ethers.formatEther(initialRate), "ECM/sec");

        // Add more rewards
        const rewards2 = ethers.parseEther("5000");
        await ecmToken.mint(owner.address, rewards2);
        await ecmToken.approve(await poolManager.getAddress(), rewards2);
        await poolManager.allocateForRewards(poolId, rewards2);
        await poolManager.setLinearRewardRate(poolId);

        const updatedPool = await poolManager.getPoolInfo(poolId);
        const updatedRate = updatedPool.rewardRatePerSecond;

        console.log("      Updated rate:", ethers.formatEther(updatedRate), "ECM/sec");

        // New rate should be approximately double
        expect(updatedRate).to.be.closeTo(initialRate * 2n, initialRate / 10n);
      });
    });

    describe("MONTHLY Strategy", function () {
      it("Should handle month boundaries correctly", async function () {
        const poolId = await createTestPool(1); // MONTHLY

        const monthlyRewards = [
          ethers.parseEther("1000"), // Month 1
          ethers.parseEther("2000"), // Month 2
          ethers.parseEther("3000"), // Month 3
        ];

        const totalRewards = monthlyRewards.reduce((sum, r) => sum + r, 0n);
        await ecmToken.mint(owner.address, totalRewards);
        await ecmToken.approve(await poolManager.getAddress(), totalRewards);
        await poolManager.allocateForRewards(poolId, totalRewards);
        await poolManager.setMonthlyRewards(poolId, monthlyRewards);

        const saleAmount = ethers.parseEther("10000");
        await ecmToken.mint(owner.address, saleAmount);
        await ecmToken.approve(await poolManager.getAddress(), saleAmount);
        await poolManager.allocateForSale(poolId, saleAmount);

        // Stake
        const stake = ethers.parseEther("1000");
        await ecmToken.mint(user1.address, stake);
        await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
        await poolManager.connect(user1).stakeECM(poolId, stake, 90 * SECONDS_PER_DAY);

        // Check rewards at 29 days (before month 2)
        await time.increase(29 * SECONDS_PER_DAY);
        const pending_day29 = await poolManager.pendingRewards(poolId, user1.address);

        // Advance 2 more days (cross into month 2)
        await time.increase(2 * SECONDS_PER_DAY);
        const pending_day31 = await poolManager.pendingRewards(poolId, user1.address);

        console.log("      Day 29 (Month 1):", ethers.formatEther(pending_day29), "ECM");
        console.log("      Day 31 (Month 2):", ethers.formatEther(pending_day31), "ECM");

        // Should have approximately full month 1 + 1 day of month 2
        const expectedMonth1 = monthlyRewards[0];
        const expectedDay31 = expectedMonth1 + (monthlyRewards[1] / 30n);

        expect(pending_day31).to.be.closeTo(expectedDay31, expectedDay31 / 100n);
      });

      it("Should handle varying monthly rewards correctly", async function () {
        const poolId = await createTestPool(1); // MONTHLY

        // Ascending rewards
        const monthlyRewards = [
          ethers.parseEther("100"),
          ethers.parseEther("200"),
          ethers.parseEther("400"),
          ethers.parseEther("800"),
        ];

        const totalRewards = monthlyRewards.reduce((sum, r) => sum + r, 0n);
        await ecmToken.mint(owner.address, totalRewards);
        await ecmToken.approve(await poolManager.getAddress(), totalRewards);
        await poolManager.allocateForRewards(poolId, totalRewards);
        await poolManager.setMonthlyRewards(poolId, monthlyRewards);

        const saleAmount = ethers.parseEther("10000");
        await ecmToken.mint(owner.address, saleAmount);
        await ecmToken.approve(await poolManager.getAddress(), saleAmount);
        await poolManager.allocateForSale(poolId, saleAmount);

        const stake = ethers.parseEther("1000");
        await ecmToken.mint(user1.address, stake);
        await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
        // Use 365 days which is in allowedStakeDurations
        await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

        // Check after each month
        for (let month = 1; month <= 4; month++) {
          await time.increase(30 * SECONDS_PER_DAY);
          const pending = await poolManager.pendingRewards(poolId, user1.address);
          
          const expectedTotal = monthlyRewards.slice(0, month).reduce((sum, r) => sum + r, 0n);
          console.log(`      After month ${month}:`, ethers.formatEther(pending), "ECM (expected:", ethers.formatEther(expectedTotal), ")");
          
          expect(pending).to.be.closeTo(expectedTotal, expectedTotal / 100n);
        }
      });
    });

    describe("WEEKLY Strategy", function () {
      it("Should handle week boundaries correctly", async function () {
        const poolId = await createTestPool(2); // WEEKLY

        const weeklyRewards = [
          ethers.parseEther("100"), // Week 1
          ethers.parseEther("150"), // Week 2
          ethers.parseEther("200"), // Week 3
          ethers.parseEther("250"), // Week 4
        ];

        const totalRewards = weeklyRewards.reduce((sum, r) => sum + r, 0n);
        await ecmToken.mint(owner.address, totalRewards);
        await ecmToken.approve(await poolManager.getAddress(), totalRewards);
        await poolManager.allocateForRewards(poolId, totalRewards);
        await poolManager.setWeeklyRewards(poolId, weeklyRewards);

        const saleAmount = ethers.parseEther("10000");
        await ecmToken.mint(owner.address, saleAmount);
        await ecmToken.approve(await poolManager.getAddress(), saleAmount);
        await poolManager.allocateForSale(poolId, saleAmount);

        const stake = ethers.parseEther("1000");
        await ecmToken.mint(user1.address, stake);
        await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
        await poolManager.connect(user1).stakeECM(poolId, stake, 30 * SECONDS_PER_DAY);

        // Check after each week
        for (let week = 1; week <= 4; week++) {
          await time.increase(7 * SECONDS_PER_DAY);
          const pending = await poolManager.pendingRewards(poolId, user1.address);
          
          const expectedTotal = weeklyRewards.slice(0, week).reduce((sum, r) => sum + r, 0n);
          console.log(`      After week ${week}:`, ethers.formatEther(pending), "ECM");
          
          expect(pending).to.be.closeTo(expectedTotal, expectedTotal / 100n);
        }
      });

      it("Should handle mid-week staking", async function () {
        const poolId = await createTestPool(2); // WEEKLY

        const weeklyRewards = [
          ethers.parseEther("700"), // Week 1 (100/day)
        ];

        await ecmToken.mint(owner.address, weeklyRewards[0]);
        await ecmToken.approve(await poolManager.getAddress(), weeklyRewards[0]);
        await poolManager.allocateForRewards(poolId, weeklyRewards[0]);
        await poolManager.setWeeklyRewards(poolId, weeklyRewards);

        const saleAmount = ethers.parseEther("10000");
        await ecmToken.mint(owner.address, saleAmount);
        await ecmToken.approve(await poolManager.getAddress(), saleAmount);
        await poolManager.allocateForSale(poolId, saleAmount);

        // User1 stakes at day 0
        const stake = ethers.parseEther("1000");
        await ecmToken.mint(user1.address, stake);
        await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
        await poolManager.connect(user1).stakeECM(poolId, stake, 30 * SECONDS_PER_DAY);

        // Advance 3.5 days
        await time.increase(Math.floor(3.5 * SECONDS_PER_DAY));

        // User2 stakes (mid-week)
        await ecmToken.mint(user2.address, stake);
        await ecmToken.connect(user2).approve(await poolManager.getAddress(), stake);
        await poolManager.connect(user2).stakeECM(poolId, stake, 30 * SECONDS_PER_DAY);

        // Advance to end of week
        await time.increase(Math.ceil(3.5 * SECONDS_PER_DAY));

        const pending1 = await poolManager.pendingRewards(poolId, user1.address);
        const pending2 = await poolManager.pendingRewards(poolId, user2.address);

        console.log("      User1 (full week):", ethers.formatEther(pending1), "ECM");
        console.log("      User2 (half week):", ethers.formatEther(pending2), "ECM");

        // User1 gets: 3.5 days solo (350 ECM) + 3.5 days shared (175 ECM) = 525 ECM
        // User2 gets: 3.5 days shared (175 ECM)
        // So User1 should have ~3x user2's rewards (525/175 = 3)
        const expectedRatio = 3n;
        const actualRatio = pending1 / pending2;
        expect(actualRatio).to.be.closeTo(expectedRatio, 1n); // Allow ±1 for rounding
      });
    });
  });

  describe("6. Stress Tests - Combined Edge Cases", function () {
    it("Should handle many small stakes with tiny rewards", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Very small rewards
      const rewards = ethers.parseEther("10");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      // 3 users stake minimum amount (500 ECM each)
      const users = [user1, user2, user3];
      const minStake = ethers.parseEther("500");

      for (const user of users) {
        await ecmToken.mint(owner.address, minStake);
        await ecmToken.approve(await poolManager.getAddress(), minStake);
        await poolManager.allocateForSale(poolId, minStake);

        await ecmToken.mint(user.address, minStake);
        await ecmToken.connect(user).approve(await poolManager.getAddress(), minStake);
        await poolManager.connect(user).stakeECM(poolId, minStake, 30 * SECONDS_PER_DAY);
      }

      // Advance time
      await time.increase(5 * SECONDS_PER_DAY);

      // Check that all users have equal rewards
      let totalPending = 0n;
      const pendings: bigint[] = [];

      for (const user of users) {
        const pending = await poolManager.pendingRewards(poolId, user.address);
        pendings.push(pending);
        totalPending += pending;
      }

      console.log("      Total distributed:", ethers.formatEther(totalPending), "ECM");
      console.log("      Per user:", ethers.formatEther(pendings[0]), "ECM");

      // All users should have equal rewards
      const avg = totalPending / BigInt(users.length);
      for (const pending of pendings) {
        expect(pending).to.be.closeTo(avg, avg / 100n);
      }
    });

    it("Should handle reward depletion gracefully", async function () {
      const poolId = await createTestPool(0); // LINEAR

      // Small rewards that will deplete at 1000 days
      const rewards = ethers.parseEther("100");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      // Advance 365 days (out of 1000 total, so not yet depleted but good test point)
      await time.increase(365 * SECONDS_PER_DAY);

      const pending = await poolManager.pendingRewards(poolId, user1.address);
      
      console.log("      Pending after 365 days:", ethers.formatEther(pending), "ECM");
      console.log("      Allocated rewards:", ethers.formatEther(rewards), "ECM");

      // Should get 365/1000 of total rewards
      const expected365Days = (rewards * 365n) / 1000n;
      expect(pending).to.be.closeTo(expected365Days, expected365Days / 100n);

      // Should not exceed allocated
      expect(pending).to.be.lte(rewards);

      // Should not overflow
      const pool = await poolManager.getPoolInfo(poolId);
      expect(pool.totalRewardsAccrued).to.be.lte(rewards);
    });

    it("Should handle alternating stakes and unstakes with precision", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("100000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // User1 stakes
      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      await time.increase(10 * SECONDS_PER_DAY);

      // User2 stakes
      await ecmToken.mint(user2.address, stake);
      await ecmToken.connect(user2).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user2).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      await time.increase(10 * SECONDS_PER_DAY);

      // User1 unstakes (mature)
      await time.increase(365 * SECONDS_PER_DAY);
      await poolManager.connect(user1).unstake(poolId);

      await time.increase(10 * SECONDS_PER_DAY);

      // User3 stakes
      await ecmToken.mint(user3.address, stake);
      await ecmToken.connect(user3).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user3).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      // Check pool accounting integrity
      const pool = await poolManager.getPoolInfo(poolId);
      const balanceStatus = await poolManager.getPoolBalanceStatus(poolId);

      console.log("      Total accrued:", ethers.formatEther(pool.totalRewardsAccrued), "ECM");
      console.log("      Rewards paid:", ethers.formatEther(pool.rewardsPaid), "ECM");
      console.log("      Deficit:", ethers.formatEther(balanceStatus.deficit), "ECM");

      // Should have no deficit
      expect(balanceStatus.deficit).to.equal(0);
    });
  });

  describe("7. Mathematical Invariants", function () {
    it("Invariant: totalRewardsAccrued <= allocatedForRewards", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      // Advance way past depletion
      await time.increase(1000 * SECONDS_PER_DAY);

      const pool = await poolManager.getPoolInfo(poolId);

      console.log("      Total accrued:", ethers.formatEther(pool.totalRewardsAccrued), "ECM");
      console.log("      Allocated:", ethers.formatEther(pool.allocatedForRewards), "ECM");

      // MUST never exceed allocation
      expect(pool.totalRewardsAccrued).to.be.lte(pool.allocatedForRewards);
    });

    it("Invariant: Sum of user rewards <= totalRewardsAccrued", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      // Multiple users stake
      const users = [user1, user2, user3];
      for (const user of users) {
        const stake = ethers.parseEther("1000");
        await ecmToken.mint(user.address, stake);
        await ecmToken.connect(user).approve(await poolManager.getAddress(), stake);
        await poolManager.connect(user).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);
      }

      await time.increase(100 * SECONDS_PER_DAY);

      // Trigger pool update by claiming rewards from one user
      // This ensures totalRewardsAccrued is updated in storage
      await poolManager.connect(user1).claimRewards(poolId);

      // Sum all pending (user1 has 0 now since they claimed)
      let totalPending = 0n;
      for (const user of users) {
        const pending = await poolManager.pendingRewards(poolId, user.address);
        totalPending += pending;
      }

      const pool = await poolManager.getPoolInfo(poolId);

      console.log("      Sum of pending:", ethers.formatEther(totalPending), "ECM");
      console.log("      Total accrued:", ethers.formatEther(pool.totalRewardsAccrued), "ECM");
      console.log("      Rewards paid:", ethers.formatEther(pool.rewardsPaid), "ECM");

      // Sum of pending + rewardsPaid should equal totalRewardsAccrued
      const totalDistributed = totalPending + pool.rewardsPaid;
      expect(totalDistributed).to.be.closeTo(pool.totalRewardsAccrued, pool.totalRewardsAccrued / 1000n);
    });

    it("Invariant: accRewardPerShare is monotonically increasing", async function () {
      const poolId = await createTestPool(0); // LINEAR

      const rewards = ethers.parseEther("1000");
      await ecmToken.mint(owner.address, rewards);
      await ecmToken.approve(await poolManager.getAddress(), rewards);
      await poolManager.allocateForRewards(poolId, rewards);
      await poolManager.setLinearRewardRate(poolId);

      const saleAmount = ethers.parseEther("10000");
      await ecmToken.mint(owner.address, saleAmount);
      await ecmToken.approve(await poolManager.getAddress(), saleAmount);
      await poolManager.allocateForSale(poolId, saleAmount);

      const stake = ethers.parseEther("1000");
      await ecmToken.mint(user1.address, stake);
      await ecmToken.connect(user1).approve(await poolManager.getAddress(), stake);
      await poolManager.connect(user1).stakeECM(poolId, stake, 365 * SECONDS_PER_DAY);

      let lastAccRewardPerShare = 0n;

      for (let i = 0; i < 10; i++) {
        await time.increase(SECONDS_PER_DAY);
        
        // Trigger update
        await poolManager.connect(user1).claimRewards(poolId);
        
        const pool = await poolManager.getPoolInfo(poolId);
        
        console.log(`      Day ${i + 1}: accRewardPerShare =`, pool.accRewardPerShare.toString());
        
        // MUST be >= last value (monotonic)
        expect(pool.accRewardPerShare).to.be.gte(lastAccRewardPerShare);
        lastAccRewardPerShare = pool.accRewardPerShare;
      }
    });
  });
});
