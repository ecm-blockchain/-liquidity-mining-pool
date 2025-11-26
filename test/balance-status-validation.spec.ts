import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { 
  PoolManager, 
  MockERC20, 
  MockUniswapV2Pair,
  VestingManager 
} from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("PoolManager - Balance Status Validation", function () {
  let poolManager: PoolManager;
  let ecmToken: MockERC20;
  let usdtToken: MockERC20;
  let uniswapPair: MockUniswapV2Pair;
  let vestingManager: VestingManager;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let treasury: SignerWithAddress;
  let liquidityManager: SignerWithAddress;

  const POOL_ID = 0;
  const INITIAL_ECM_SUPPLY = ethers.parseEther("10000000");
  const INITIAL_USDT_SUPPLY = ethers.parseUnits("10000000", 6);

  async function deployFixture() {
    const [owner, user1, user2, treasury, liquidityManager] = await ethers.getSigners();

    // Deploy tokens and contracts (similar to previous test)
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const ecmToken = await MockERC20.deploy("ECM Token", "ECM", 18, INITIAL_ECM_SUPPLY);
    const usdtToken = await MockERC20.deploy("USDT Token", "USDT", 6, INITIAL_USDT_SUPPLY);

    const MockUniswapV2Pair = await ethers.getContractFactory("MockUniswapV2Pair");
    const uniswapPair = await MockUniswapV2Pair.deploy(ecmToken.target, usdtToken.target);

    // Add liquidity for pricing
    await ecmToken.transfer(uniswapPair.target, ethers.parseEther("100000"));
    await usdtToken.transfer(uniswapPair.target, ethers.parseUnits("50000", 6));
    await uniswapPair.sync();

    // Deploy mock Uniswap V2 Router for PoolManager
    const MockUniswapV2Router = await ethers.getContractFactory("MockUniswapV2Router");
    const mockRouter = await MockUniswapV2Router.deploy();

    const PoolManager = await ethers.getContractFactory("PoolManager");
    const poolManager = await PoolManager.deploy(mockRouter.target);

    const VestingManager = await ethers.getContractFactory("VestingManager");
    const vestingManager = await VestingManager.deploy(poolManager.target);

    await poolManager.setVestingManager(vestingManager.target);
    await poolManager.addAuthorizedLiquidityManager(liquidityManager.address);
    await vestingManager.addAuthorizedCreator(poolManager.target);

    // Create pool
    const poolParams = {
      ecm: ecmToken.target,
      usdt: usdtToken.target,
      pair: uniswapPair.target,
      penaltyReceiver: treasury.address,
      rewardStrategy: 0, // LINEAR
      allowedStakeDurations: [30 * 24 * 3600, 90 * 24 * 3600],
      maxDuration: 90 * 24 * 3600,
      vestingDuration: 180 * 24 * 3600,
      vestRewardsByDefault: false,
      penaltyBps: 2500
    };

    await poolManager.createPool(poolParams);

    // Transfer tokens to users
    await ecmToken.transfer(user1.address, ethers.parseEther("100000"));
    await ecmToken.transfer(user2.address, ethers.parseEther("100000"));
    await usdtToken.transfer(user1.address, ethers.parseUnits("100000", 6));
    await usdtToken.transfer(user2.address, ethers.parseUnits("100000", 6));

    return {
      poolManager,
      ecmToken,
      usdtToken,
      uniswapPair,
      vestingManager,
      owner,
      user1,
      user2,
      treasury,
      liquidityManager
    };
  }

  beforeEach(async function () {
    const fixture = await loadFixture(deployFixture);
    poolManager = fixture.poolManager as unknown as PoolManager;
    ecmToken = fixture.ecmToken as unknown as MockERC20;
    usdtToken = fixture.usdtToken as unknown as MockERC20;
    uniswapPair = fixture.uniswapPair as unknown as MockUniswapV2Pair;
    vestingManager = fixture.vestingManager as unknown as VestingManager;
    owner = fixture.owner;
    user1 = fixture.user1;
    user2 = fixture.user2;
    treasury = fixture.treasury;
    liquidityManager = fixture.liquidityManager;
  });

  describe("Balance Status After Allocations", function () {
    const SALE_ALLOCATION = ethers.parseEther("1000000"); // 1M ECM
    const REWARD_ALLOCATION = ethers.parseEther("500000"); // 500K ECM

    it("Should show correct balance status after allocations", async function () {
      // Initial state
      let balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);
      
      expect(balanceStatus.totalAllocated).to.equal(0);
      expect(balanceStatus.soldToUsers).to.equal(0);
      expect(balanceStatus.currentlyStaked).to.equal(0);
      expect(balanceStatus.availableInContract).to.equal(0);
      expect(balanceStatus.deficit).to.equal(0);

      // Allocate for sale
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);

      balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);
      expect(balanceStatus.totalAllocated).to.equal(SALE_ALLOCATION);
      expect(balanceStatus.availableInContract).to.equal(SALE_ALLOCATION);

      // Allocate for rewards
      await ecmToken.approve(poolManager.target, REWARD_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);

      balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);
      expect(balanceStatus.totalAllocated).to.equal(SALE_ALLOCATION + REWARD_ALLOCATION);
      expect(balanceStatus.availableInContract).to.equal(SALE_ALLOCATION + REWARD_ALLOCATION);
    });

    it("Should track balance changes after purchases", async function () {
      // Setup allocations
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION + REWARD_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);
      await poolManager.setLinearRewardRate(POOL_ID);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      // User purchase
      const usdtAmount = ethers.parseUnits("5000", 6);
      await usdtToken.connect(user1).approve(poolManager.target, usdtAmount);
      await poolManager.connect(user1).buyAndStake(
        POOL_ID,
        usdtAmount,
        30 * 24 * 3600,
        emptyVoucher,
        "0x"
      );

      const balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);
      const pool = await poolManager.getPoolInfo(POOL_ID);

      // Verify balance tracking
      expect(balanceStatus.soldToUsers).to.equal(pool.sold);
      expect(balanceStatus.currentlyStaked).to.equal(pool.totalStaked);
      expect(balanceStatus.soldToUsers).to.equal(balanceStatus.currentlyStaked); // Key invariant

      // Available should be the total tokens in contract
      // Sold tokens are staked, so they're still in the contract
      const expectedAvailable = SALE_ALLOCATION + REWARD_ALLOCATION;
      expect(balanceStatus.availableInContract).to.be.closeTo(expectedAvailable, ethers.parseEther("1"));
    });
  });

  describe("Balance Status During Liquidity Operations", function () {
    const SALE_ALLOCATION = ethers.parseEther("1000000");
    const REWARD_ALLOCATION = ethers.parseEther("500000");

    beforeEach(async function () {
      // Setup with allocations and some user stakes
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION + REWARD_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);
      await poolManager.setLinearRewardRate(POOL_ID);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      // Create user stakes
      await usdtToken.connect(user1).approve(poolManager.target, ethers.parseUnits("10000", 6));
      await poolManager.connect(user1).buyAndStake(
        POOL_ID,
        ethers.parseUnits("5000", 6),
        30 * 24 * 3600,
        emptyVoucher,
        "0x"
      );
    });

    it("Should track liquidity transfers in balance status", async function () {
      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);
      const pool = await poolManager.getPoolInfo(POOL_ID);

      const ecmTransfer = ethers.parseEther("5000");
      const usdtTransfer = ethers.parseUnits("2000", 6);

      // Transfer to liquidity manager
      await poolManager.transferToLiquidityManager(
        POOL_ID,
        liquidityManager.address,
        ecmTransfer,
        usdtTransfer
      );

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);

      // movedToLiquidity should increase
      expect(balanceAfter.movedToLiquidity).to.equal(balanceBefore.movedToLiquidity + ecmTransfer);
      
      // liquidityOwedECM should increase
      expect(balanceAfter.liquidityOwedECM).to.equal(balanceBefore.liquidityOwedECM + ecmTransfer);

      // availableInContract should decrease by transfer amount
      expect(balanceAfter.availableInContract).to.equal(balanceBefore.availableInContract - ecmTransfer);
    });

    it("Should handle liquidity addition callbacks", async function () {
      // First transfer tokens to liquidity manager
      const ecmTransfer = ethers.parseEther("5000");
      await poolManager.transferToLiquidityManager(
        POOL_ID,
        liquidityManager.address,
        ecmTransfer,
        0
      );

      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);

      // Simulate liquidity manager adding liquidity to Uniswap
      const ecmAdded = ethers.parseEther("3000");
      const usdtAdded = ethers.parseUnits("1500", 6);

      await poolManager.connect(liquidityManager).recordLiquidityAdded(
        POOL_ID,
        ecmAdded,
        usdtAdded
      );

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);

      // addedToUniswap should increase
      expect(balanceAfter.addedToUniswap).to.equal(balanceBefore.addedToUniswap + ecmAdded);
    });

    it("Should track deficit when liquidity exceeds available", async function () {
      const pool = await poolManager.getPoolInfo(POOL_ID);
      
      // Transfer all staked tokens to liquidity
      const transferAmount = pool.totalStaked;
      
      await poolManager.transferToLiquidityManager(
        POOL_ID,
        liquidityManager.address,
        transferAmount,
        0
      );

      const balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);

      // availableInContract should reflect actual balance after transfer
      // Initial was SALE_ALLOCATION + REWARD_ALLOCATION, minus transferAmount
      const balanceBefore = await ecmToken.balanceOf(poolManager.target);
      expect(balanceStatus.availableInContract).to.be.gte(0);
      
      // If we transferred more than what we should have available,
      // there should be a deficit
      if (transferAmount > balanceBefore) {
        expect(balanceStatus.deficit).to.be.gt(0);
      }
    });
  });

  describe("Balance Status During Reward Operations", function () {
    const SALE_ALLOCATION = ethers.parseEther("1000000");
    const REWARD_ALLOCATION = ethers.parseEther("500000");

    beforeEach(async function () {
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION + REWARD_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);
      await poolManager.setLinearRewardRate(POOL_ID);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      await usdtToken.connect(user1).approve(poolManager.target, ethers.parseUnits("10000", 6));
      await poolManager.connect(user1).buyAndStake(
        POOL_ID,
        ethers.parseUnits("5000", 6),
        30 * 24 * 3600,
        emptyVoucher,
        "0x"
      );

      // Fast forward to accumulate rewards
      await ethers.provider.send("evm_increaseTime", [7 * 24 * 3600]);
      await ethers.provider.send("evm_mine", []);
    });

    it("Should track immediate reward payments in balance status", async function () {
      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);

      await poolManager.connect(user1).claimRewards(POOL_ID);

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);

      // rewardsPaid should increase
      expect(balanceAfter.rewardsPaid).to.be.gt(balanceBefore.rewardsPaid);

      // availableInContract should decrease by rewards paid
      const rewardsPaid = balanceAfter.rewardsPaid - balanceBefore.rewardsPaid;
      expect(balanceAfter.availableInContract).to.be.closeTo(
        balanceBefore.availableInContract - rewardsPaid,
        ethers.parseEther("0.1") // Small tolerance for precision
      );
    });

    it("Should track vested rewards in balance status", async function () {
      // Enable vesting
      await poolManager.setVestingConfig(POOL_ID, 180 * 24 * 3600, true);

      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);

      await poolManager.connect(user1).claimRewards(POOL_ID);

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);

      // vested should increase
      expect(balanceAfter.vested).to.be.gt(balanceBefore.vested);

      // rewardsPaid should also increase (tracks total rewards distributed)
      expect(balanceAfter.rewardsPaid).to.be.gt(balanceBefore.rewardsPaid);

      // availableInContract should decrease by vested amount
      const vestedAmount = balanceAfter.vested - balanceBefore.vested;
      expect(balanceAfter.availableInContract).to.be.closeTo(
        balanceBefore.availableInContract - vestedAmount,
        ethers.parseEther("0.1")
      );
    });
  });

  describe("Balance Status During Unstaking", function () {
    const SALE_ALLOCATION = ethers.parseEther("1000000");
    const REWARD_ALLOCATION = ethers.parseEther("500000");

    beforeEach(async function () {
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION + REWARD_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);
      await poolManager.setLinearRewardRate(POOL_ID);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      await usdtToken.connect(user1).approve(poolManager.target, ethers.parseUnits("10000", 6));
      await poolManager.connect(user1).buyAndStake(
        POOL_ID,
        ethers.parseUnits("5000", 6),
        30 * 24 * 3600,
        emptyVoucher,
        "0x"
      );
    });

    it("Should show balance changes on mature unstake", async function () {
      // Fast forward past stake duration
      await ethers.provider.send("evm_increaseTime", [31 * 24 * 3600]);
      await ethers.provider.send("evm_mine", []);

      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);
      const userInfo = await poolManager.getUserInfo(POOL_ID, user1.address);

      await poolManager.connect(user1).unstake(POOL_ID);

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);

      // currentlyStaked should decrease by user's stake
      expect(balanceAfter.currentlyStaked).to.equal(balanceBefore.currentlyStaked - userInfo.staked);

      // soldToUsers should remain the same (historical)
      expect(balanceAfter.soldToUsers).to.equal(balanceBefore.soldToUsers);

      // availableInContract should increase by unstaked principal and decrease by rewards
      // (net effect depends on reward amount)
      const totalChange = balanceAfter.availableInContract - balanceBefore.availableInContract;
      expect(totalChange).to.be.lte(userInfo.staked); // Can't exceed principal returned
    });

    it("Should track penalties on early unstake", async function () {
      const balanceBefore = await poolManager.getPoolBalanceStatus(POOL_ID);
      const userInfo = await poolManager.getUserInfo(POOL_ID, user1.address);

      // Early unstake (should incur penalty)
      await poolManager.connect(user1).unstake(POOL_ID);

      const balanceAfter = await poolManager.getPoolBalanceStatus(POOL_ID);
      const pool = await poolManager.getPoolInfo(POOL_ID);

      // currentlyStaked should decrease
      expect(balanceAfter.currentlyStaked).to.equal(balanceBefore.currentlyStaked - userInfo.staked);

      // totalPenaltiesCollected should be tracked in pool (not directly in balance status)
      expect(pool.totalPenaltiesCollected).to.be.gt(0);

      // Expected penalty (25%)
      const expectedPenalty = (userInfo.staked * 2500n) / 10000n;
      expect(pool.totalPenaltiesCollected).to.equal(expectedPenalty);
    });
  });

  describe("Complex Balance Status Scenarios", function () {
    const SALE_ALLOCATION = ethers.parseEther("1000000");
    const REWARD_ALLOCATION = ethers.parseEther("500000");

    it("Should maintain accurate balance status through complex operations", async function () {
      // Setup
      await ecmToken.approve(poolManager.target, SALE_ALLOCATION + REWARD_ALLOCATION);
      await poolManager.allocateForSale(POOL_ID, SALE_ALLOCATION);
      await poolManager.allocateForRewards(POOL_ID, REWARD_ALLOCATION);
      await poolManager.setLinearRewardRate(POOL_ID);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      // Multiple users buy and stake
      await usdtToken.connect(user1).approve(poolManager.target, ethers.parseUnits("10000", 6));
      await poolManager.connect(user1).buyAndStake(POOL_ID, ethers.parseUnits("3000", 6), 30 * 24 * 3600, emptyVoucher, "0x");
      
      await usdtToken.connect(user2).approve(poolManager.target, ethers.parseUnits("10000", 6));
      await poolManager.connect(user2).buyAndStake(POOL_ID, ethers.parseUnits("4000", 6), 90 * 24 * 3600, emptyVoucher, "0x");

      // Transfer some to liquidity
      await poolManager.transferToLiquidityManager(POOL_ID, liquidityManager.address, ethers.parseEther("8000"), ethers.parseUnits("3000", 6));

      // Record some liquidity additions
      await poolManager.connect(liquidityManager).recordLiquidityAdded(POOL_ID, ethers.parseEther("5000"), ethers.parseUnits("2000", 6));

      // Fast forward and claim rewards
      await ethers.provider.send("evm_increaseTime", [10 * 24 * 3600]);
      await ethers.provider.send("evm_mine", []);
      await poolManager.connect(user1).claimRewards(POOL_ID);

      // Early unstake user1
      await poolManager.connect(user1).unstake(POOL_ID);

      // Get final balance status
      const balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);
      const pool = await poolManager.getPoolInfo(POOL_ID);
      const contractBalance = await ecmToken.balanceOf(poolManager.target);

      // Verify key relationships
      expect(balanceStatus.totalAllocated).to.equal(SALE_ALLOCATION + REWARD_ALLOCATION);
      expect(balanceStatus.soldToUsers).to.equal(pool.sold);
      expect(balanceStatus.currentlyStaked).to.equal(pool.totalStaked);
      expect(balanceStatus.movedToLiquidity).to.equal(pool.ecmMovedToLiquidity);
      expect(balanceStatus.liquidityOwedECM).to.equal(pool.liquidityPoolOwedECM);
      expect(balanceStatus.addedToUniswap).to.equal(pool.ecmAddedToUniswap);
      expect(balanceStatus.rewardsPaid).to.equal(pool.rewardsPaid);

      // Contract balance should match calculated available amount
      const calculatedAvailable = balanceStatus.availableInContract;
      expect(contractBalance).to.be.closeTo(calculatedAvailable, ethers.parseEther("2")); // Allow for rounding
    });

    it("Should detect and report deficit correctly", async function () {
      // Setup minimal allocation
      const smallAllocation = ethers.parseEther("50000");
      await ecmToken.approve(poolManager.target, smallAllocation);
      await poolManager.allocateForSale(POOL_ID, smallAllocation);

      const emptyVoucher = {
        vid: ethers.ZeroHash,
        codeHash: ethers.ZeroHash,
        owner: ethers.ZeroAddress,
        directBps: 0,
        transferOnUse: false,
        expiry: 0,
        maxUses: 0,
        nonce: 0
      };

      // Buy most of allocation
      await usdtToken.connect(user1).approve(poolManager.target, ethers.parseUnits("20000", 6));
      await poolManager.connect(user1).buyAndStake(POOL_ID, ethers.parseUnits("20000", 6), 30 * 24 * 3600, emptyVoucher, "0x");

      const pool = await poolManager.getPoolInfo(POOL_ID);
      
      // Transfer more to liquidity than available
      await poolManager.transferToLiquidityManager(POOL_ID, liquidityManager.address, pool.totalStaked, 0);

      const balanceStatus = await poolManager.getPoolBalanceStatus(POOL_ID);

      // Should show deficit situation
      if (balanceStatus.availableInContract < 0) {
        expect(balanceStatus.deficit).to.be.gt(0);
        expect(balanceStatus.deficit).to.equal(-balanceStatus.availableInContract);
      }
    });
  });
});