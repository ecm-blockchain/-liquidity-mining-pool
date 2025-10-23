# Off-Chain Analytics & Calculations Guide

## Overview

This document provides a comprehensive guide to all calculations that can be performed off-chain for better analytics, estimations, and user/admin dashboards for the ECM Liquidity Mining Pool system.

The system consists of three main contracts:
- **PoolManager**: Token sale, staking, and reward distribution
- **ReferralModule**: Referral tracking and commission management
- **VestingManager**: Linear vesting of reward tokens

---

## Table of Contents

1. [PoolManager Off-Chain Calculations](#poolmanager-off-chain-calculations)
   - [Price & Purchase Estimations](#1-price--purchase-estimations)
   - [Reward Calculations](#2-reward-calculations)
   - [APR/APY Calculations](#3-aprapy-calculations)
   - [Pool Analytics](#4-pool-analytics)
   - [User Portfolio Analytics](#5-user-portfolio-analytics)
   - [Liquidity Tracking](#6-liquidity-tracking)
   - [Early Unstake Projections](#7-early-unstake-projections)

2. [ReferralModule Off-Chain Calculations](#referralmodule-off-chain-calculations)
   - [Commission Projections](#1-commission-projections)
   - [Referral Network Analytics](#2-referral-network-analytics)
   - [Multi-Level Commission Distribution](#3-multi-level-commission-distribution)

3. [VestingManager Off-Chain Calculations](#vestingmanager-off-chain-calculations)
   - [Vesting Schedule Projections](#1-vesting-schedule-projections)
   - [Portfolio Vesting Analytics](#2-portfolio-vesting-analytics)

4. [Cross-Contract Analytics](#cross-contract-analytics)
   - [Complete User Financial View](#1-complete-user-financial-view)
   - [System-Wide Metrics](#2-system-wide-metrics)

5. [Implementation Examples](#implementation-examples)

---

## PoolManager Off-Chain Calculations

### 1. Price & Purchase Estimations

#### A. ECM Price from Uniswap Reserves

**Purpose**: Real-time ECM/USDT price for UI display and purchase calculations

**On-Chain Data Required**:
```javascript
const pair = await ethers.getContractAt("IUniswapV2Pair", pool.pair);
const [reserve0, reserve1] = await pair.getReserves();
const token0 = await pair.token0();
```

**Off-Chain Calculation**:
```javascript
// Determine which reserve is ECM and which is USDT
const [reserveECM, reserveUSDT] = token0.toLowerCase() === ecmAddress.toLowerCase()
  ? [reserve0, reserve1]
  : [reserve1, reserve0];

// Price in USDT per ECM (with decimals consideration)
const priceUSDTPerECM = (reserveUSDT * 1e18) / reserveECM;

// Price in ECM per USDT
const priceECMPerUSDT = (reserveECM * 1e6) / reserveUSDT; // Assuming USDT is 6 decimals
```

**Use Cases**:
- Display current ECM price on UI
- Calculate historical price movements
- Price alerts and notifications
- Market depth analysis

---

#### B. Purchase Amount Estimations

**Purpose**: Estimate ECM amount for given USDT or vice versa

**Formula (ECM for USDT with 0.3% fee)**:
```javascript
function estimateECMForUSDT(usdtAmount, reserveUSDT, reserveECM) {
  const amountInWithFee = usdtAmount * 997n;
  const numerator = amountInWithFee * reserveECM;
  const denominator = (reserveUSDT * 1000n) + amountInWithFee;
  return numerator / denominator;
}
```

**Formula (USDT for exact ECM)**:
```javascript
function estimateUSDTForECM(ecmAmount, reserveUSDT, reserveECM) {
  const numerator = reserveUSDT * ecmAmount * 1000n;
  const denominator = (reserveECM - ecmAmount) * 997n;
  return (numerator / denominator) + 1n; // +1 for rounding
}
```

**Minimum Purchase Validation**:
```javascript
function validateMinimumPurchase(ecmAmount) {
  const MIN_PURCHASE_ECM = ethers.parseEther("500");
  return ecmAmount >= MIN_PURCHASE_ECM;
}
```

**Use Cases**:
- Purchase calculator on UI
- Pre-transaction validation
- Slippage estimation
- Gas cost vs purchase amount optimization

---

#### C. Slippage Calculations

**Purpose**: Calculate price impact and slippage for different purchase sizes

**Off-Chain Calculation**:
```javascript
function calculateSlippage(usdtAmount, reserveUSDT, reserveECM) {
  // Price before trade
  const priceBefore = (reserveUSDT * 1e18) / reserveECM;
  
  // ECM received
  const ecmOut = estimateECMForUSDT(usdtAmount, reserveUSDT, reserveECM);
  
  // Price after trade (simulate new reserves)
  const newReserveUSDT = reserveUSDT + usdtAmount;
  const newReserveECM = reserveECM - ecmOut;
  const priceAfter = (newReserveUSDT * 1e18) / newReserveECM;
  
  // Price impact percentage
  const priceImpact = ((priceAfter - priceBefore) * 10000n) / priceBefore;
  
  // Effective price per ECM
  const effectivePrice = (usdtAmount * 1e18) / ecmOut;
  
  // Slippage percentage
  const slippage = ((effectivePrice - priceBefore) * 10000n) / priceBefore;
  
  return {
    priceBefore,
    priceAfter,
    priceImpact: Number(priceImpact) / 100, // in bps
    slippage: Number(slippage) / 100, // in bps
    effectivePrice
  };
}
```

**Use Cases**:
- Display slippage warnings
- Dynamic slippage tolerance suggestions
- Large order optimization (split into multiple txs)

---

### 2. Reward Calculations

#### A. Pending Rewards (Real-Time)

**Purpose**: Calculate exact pending rewards for a user at any moment

**On-Chain Data Required**:
```javascript
const poolInfo = await poolManager.getPoolInfo(poolId);
const userInfo = await poolManager.getUserInfo(poolId, userAddress);
```

**Off-Chain Calculation (LINEAR Strategy)**:
```javascript
function calculatePendingRewardsLinear(poolInfo, userInfo, currentTimestamp) {
  let accRewardPerShare = poolInfo.accRewardPerShare;
  
  // Calculate updated accRewardPerShare
  if (currentTimestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0n) {
    const delta = currentTimestamp - poolInfo.lastRewardTime;
    const rewardAccrued = delta * poolInfo.rewardRatePerSecond;
    accRewardPerShare += (rewardAccrued * PRECISION) / poolInfo.totalStaked;
  }
  
  // Calculate pending rewards
  const pending = (userInfo.staked * accRewardPerShare / PRECISION) 
                  - userInfo.rewardDebt 
                  + userInfo.pendingRewards;
  
  return pending;
}
```

**Off-Chain Calculation (MONTHLY Strategy)**:
```javascript
function calculatePendingRewardsMonthly(poolInfo, userInfo, currentTimestamp) {
  let accRewardPerShare = poolInfo.accRewardPerShare;
  
  if (currentTimestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0n) {
    const delta = currentTimestamp - poolInfo.lastRewardTime;
    
    // Calculate elapsed months
    const monthsPassed = delta / (30n * 24n * 3600n);
    let totalMonthlyRewards = 0n;
    
    for (let i = 0; i < monthsPassed && poolInfo.monthlyRewardIndex + i < poolInfo.monthlyRewards.length; i++) {
      totalMonthlyRewards += poolInfo.monthlyRewards[poolInfo.monthlyRewardIndex + i];
    }
    
    // Proportional rewards within current month
    const timeInCurrentMonth = delta % (30n * 24n * 3600n);
    const currentMonthReward = poolInfo.monthlyRewards[poolInfo.monthlyRewardIndex] || 0n;
    const partialMonthReward = (currentMonthReward * timeInCurrentMonth) / (30n * 24n * 3600n);
    
    const rewardAccrued = totalMonthlyRewards + partialMonthReward;
    accRewardPerShare += (rewardAccrued * PRECISION) / poolInfo.totalStaked;
  }
  
  const pending = (userInfo.staked * accRewardPerShare / PRECISION) 
                  - userInfo.rewardDebt 
                  + userInfo.pendingRewards;
  
  return pending;
}
```

**Off-Chain Calculation (WEEKLY Strategy)**:
```javascript
function calculatePendingRewardsWeekly(poolInfo, userInfo, currentTimestamp) {
  let accRewardPerShare = poolInfo.accRewardPerShare;
  
  if (currentTimestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0n) {
    const delta = currentTimestamp - poolInfo.lastRewardTime;
    const WEEK_SECONDS = 7n * 24n * 3600n;
    
    // Calculate elapsed weeks
    const weeksPassed = delta / WEEK_SECONDS;
    let totalWeeklyRewards = 0n;
    
    for (let i = 0; i < weeksPassed && poolInfo.weeklyRewardIndex + i < poolInfo.weeklyRewards.length; i++) {
      totalWeeklyRewards += poolInfo.weeklyRewards[poolInfo.weeklyRewardIndex + i];
    }
    
    // Proportional rewards within current week
    const timeInCurrentWeek = delta % WEEK_SECONDS;
    const currentWeekReward = poolInfo.weeklyRewards[poolInfo.weeklyRewardIndex] || 0n;
    const partialWeekReward = (currentWeekReward * timeInCurrentWeek) / WEEK_SECONDS;
    
    const rewardAccrued = totalWeeklyRewards + partialWeekReward;
    accRewardPerShare += (rewardAccrued * PRECISION) / poolInfo.totalStaked;
  }
  
  const pending = (userInfo.staked * accRewardPerShare / PRECISION) 
                  - userInfo.rewardDebt 
                  + userInfo.pendingRewards;
  
  return pending;
}
```

**Use Cases**:
- Real-time reward display on dashboard
- Reward accumulation charts
- Auto-claim notifications

---

#### B. Expected Rewards (Forward Projection)

**Purpose**: Estimate rewards over a future time period

**Off-Chain Calculation (LINEAR)**:
```javascript
function projectRewardsLinear(userStaked, totalStaked, rewardRatePerSecond, durationSeconds) {
  if (totalStaked === 0n) return 0n;
  
  return (userStaked * rewardRatePerSecond * durationSeconds) / totalStaked;
}
```

**Off-Chain Calculation (MONTHLY)**:
```javascript
function projectRewardsMonthly(userStaked, totalStaked, monthlyRewards, monthlyRewardIndex, numberOfMonths) {
  if (totalStaked === 0n) return 0n;
  
  let totalRewards = 0n;
  for (let i = 0; i < numberOfMonths; i++) {
    const monthIndex = monthlyRewardIndex + i;
    if (monthIndex < monthlyRewards.length) {
      totalRewards += monthlyRewards[monthIndex];
    }
  }
  
  return (userStaked * totalRewards) / totalStaked;
}
```

**Off-Chain Calculation (WEEKLY)**:
```javascript
function projectRewardsWeekly(userStaked, totalStaked, weeklyRewards, weeklyRewardIndex, numberOfWeeks) {
  if (totalStaked === 0n) return 0n;
  
  let totalRewards = 0n;
  for (let i = 0; i < numberOfWeeks; i++) {
    const weekIndex = weeklyRewardIndex + i;
    if (weekIndex < weeklyRewards.length) {
      totalRewards += weeklyRewards[weekIndex];
    }
  }
  
  return (userStaked * totalRewards) / totalStaked;
}
```

**Use Cases**:
- Reward calculators for different stake amounts/durations
- Investment decision support
- Comparison between different pools

---

### 3. APR/APY Calculations

#### A. Annual Percentage Rate (APR)

**Purpose**: Calculate annualized return rate for comparison

**On-Chain Formula (Already Implemented)**:
```javascript
// For LINEAR strategy
const SECONDS_PER_YEAR = 31557600n; // 365.25 days
const annualRewards = pool.rewardRatePerSecond * SECONDS_PER_YEAR;
const apr = (annualRewards * PRECISION * 100n) / pool.totalStaked;

// For MONTHLY strategy (sum next 12 months)
let projectedRewards = 0n;
for (let i = 0; i < 12; i++) {
  const monthIndex = pool.monthlyRewardIndex + i;
  if (monthIndex < pool.monthlyRewards.length) {
    projectedRewards += pool.monthlyRewards[monthIndex];
  }
}
const apr = (projectedRewards * PRECISION * 100n) / pool.totalStaked;

// For WEEKLY strategy (sum next 52 weeks, annualized)
let projectedRewards = 0n;
const weeksInYear = 52n;
for (let i = 0; i < weeksInYear; i++) {
  const weekIndex = pool.weeklyRewardIndex + i;
  if (weekIndex < pool.weeklyRewards.length) {
    projectedRewards += pool.weeklyRewards[weekIndex];
  }
}
const apr = (projectedRewards * PRECISION * 100n) / pool.totalStaked;
```

**Off-Chain Enhancement - Historical APR**:
```javascript
function calculateHistoricalAPR(poolData, timestampStart, timestampEnd) {
  const duration = timestampEnd - timestampStart;
  const rewardsPaid = poolData.rewardsPaidInPeriod; // Track from events
  const avgStaked = poolData.avgStakedInPeriod; // Calculate from events
  
  // Annualize the rate
  const SECONDS_PER_YEAR = 31557600;
  const periodAPR = (rewardsPaid * 100) / avgStaked;
  const annualizedAPR = (periodAPR * SECONDS_PER_YEAR) / duration;
  
  return annualizedAPR;
}
```

---

#### B. Annual Percentage Yield (APY)

**Purpose**: Calculate compound interest rate (assuming auto-compounding)

**Off-Chain Calculation**:
```javascript
function calculateAPY(apr, compoundingFrequency = 365) {
  // APY = (1 + APR/n)^n - 1
  // Where n = compounding frequency per year
  
  const aprDecimal = apr / 100; // Convert from percentage
  const apy = Math.pow(1 + (aprDecimal / compoundingFrequency), compoundingFrequency) - 1;
  
  return apy * 100; // Return as percentage
}

// Example: Daily compounding
const apr = 50; // 50% APR
const apyDaily = calculateAPY(apr, 365); // ≈ 64.8%

// Example: Continuous compounding
const apyContinuous = (Math.exp(apr / 100) - 1) * 100; // ≈ 64.9%
```

**Use Cases**:
- Display more attractive (realistic) returns with compounding
- Compare with DeFi protocols that show APY
- Educate users on compounding benefits

---

### 4. Pool Analytics

#### A. Pool Health Metrics

**Purpose**: Monitor pool sustainability and health

**Off-Chain Calculations**:
```javascript
function calculatePoolHealth(poolInfo) {
  const totalAllocated = poolInfo.allocatedForSale + poolInfo.allocatedForRewards;
  const totalUsed = poolInfo.sold + poolInfo.rewardsPaid;
  const utilization = (totalUsed * 100n) / totalAllocated;
  
  // Reward runway (days remaining at current rate)
  const remainingRewards = poolInfo.allocatedForRewards - poolInfo.rewardsPaid;
  let rewardRunwayDays = 0;
  
  if (poolInfo.rewardStrategy === 0) { // LINEAR
    const dailyRewards = poolInfo.rewardRatePerSecond * 86400n;
    if (dailyRewards > 0n) {
      rewardRunwayDays = Number(remainingRewards / dailyRewards);
    }
  } else if (poolInfo.rewardStrategy === 1) { // MONTHLY
    // Calculate based on remaining months in schedule
    const remainingMonths = poolInfo.monthlyRewards.length - poolInfo.monthlyRewardIndex;
    rewardRunwayDays = remainingMonths * 30;
  } else if (poolInfo.rewardStrategy === 2) { // WEEKLY
    const remainingWeeks = poolInfo.weeklyRewards.length - poolInfo.weeklyRewardIndex;
    rewardRunwayDays = remainingWeeks * 7;
  }
  
  // Sale progress
  const saleProgress = (poolInfo.sold * 100n) / poolInfo.allocatedForSale;
  
  // Staking participation
  const stakingRate = poolInfo.totalStaked === poolInfo.sold ? 100 : 0; // Should be 100% since auto-stake
  
  return {
    utilization: Number(utilization),
    rewardRunwayDays,
    saleProgress: Number(saleProgress),
    stakingRate,
    totalAllocated: ethers.formatEther(totalAllocated),
    remainingRewards: ethers.formatEther(remainingRewards),
    collectedUSDT: ethers.formatUnits(poolInfo.collectedUSDT, 6)
  };
}
```

---

#### B. Liquidity Metrics

**Purpose**: Track liquidity movements and Uniswap integration

**Off-Chain Calculations**:
```javascript
function calculateLiquidityMetrics(poolInfo) {
  // Total moved to liquidity manager
  const totalECMToLiquidity = poolInfo.ecmMovedToLiquidity;
  const totalUSDTToLiquidity = poolInfo.usdtMovedToLiquidity;
  
  // Actually added to Uniswap
  const ecmInUniswap = poolInfo.ecmAddedToUniswap;
  const usdtInUniswap = poolInfo.usdtAddedToUniswap;
  
  // Pending/held by LiquidityManager
  const ecmOwedToLiquidity = poolInfo.liquidityPoolOwedECM;
  const ecmHeldByManager = totalECMToLiquidity - ecmOwedToLiquidity; // Refilled amount
  
  // Efficiency ratios
  const ecmEfficiency = totalECMToLiquidity > 0n 
    ? (ecmInUniswap * 100n) / totalECMToLiquidity 
    : 0n;
  const usdtEfficiency = totalUSDTToLiquidity > 0n 
    ? (usdtInUniswap * 100n) / totalUSDTToLiquidity 
    : 0n;
  
  return {
    totalECMToLiquidity: ethers.formatEther(totalECMToLiquidity),
    totalUSDTToLiquidity: ethers.formatUnits(totalUSDTToLiquidity, 6),
    ecmInUniswap: ethers.formatEther(ecmInUniswap),
    usdtInUniswap: ethers.formatUnits(usdtInUniswap, 6),
    ecmOwedToLiquidity: ethers.formatEther(ecmOwedToLiquidity),
    ecmEfficiency: Number(ecmEfficiency),
    usdtEfficiency: Number(usdtEfficiency)
  };
}
```

---

### 5. User Portfolio Analytics

#### A. User Position Summary

**Purpose**: Comprehensive view of user's stake and returns

**Off-Chain Calculations**:
```javascript
function calculateUserPosition(poolInfo, userInfo, currentTimestamp) {
  // Current stake value
  const stakedValue = userInfo.staked;
  
  // Pending rewards (use previous calculations)
  const pendingRewards = calculatePendingRewards(poolInfo, userInfo, currentTimestamp);
  
  // Total value (principal + rewards)
  const totalValue = stakedValue + pendingRewards;
  
  // Time remaining in stake
  const stakeEndTime = userInfo.stakeStart + userInfo.stakeDuration;
  const timeRemaining = stakeEndTime > currentTimestamp 
    ? stakeEndTime - currentTimestamp 
    : 0n;
  const isMatured = timeRemaining === 0n;
  
  // Early unstake penalty
  const penaltyBps = poolInfo.penaltyBps;
  const earlyUnstakePenalty = isMatured ? 0n : (stakedValue * BigInt(penaltyBps)) / 10000n;
  const netPrincipalIfEarlyUnstake = stakedValue - earlyUnstakePenalty;
  
  // ROI calculation
  const invested = userInfo.staked; // Original investment in ECM
  const gained = pendingRewards + userInfo.totalRewardsClaimed;
  const roi = invested > 0n ? (gained * 10000n) / invested : 0n;
  
  // Projected rewards until maturity
  const timeToMaturity = isMatured ? 0n : timeRemaining;
  const projectedRewardsToMaturity = projectRewards(poolInfo, userInfo, timeToMaturity);
  
  return {
    staked: ethers.formatEther(stakedValue),
    pendingRewards: ethers.formatEther(pendingRewards),
    totalValue: ethers.formatEther(totalValue),
    timeRemaining: Number(timeRemaining),
    timeRemainingDays: Number(timeRemaining) / 86400,
    isMatured,
    earlyUnstakePenalty: ethers.formatEther(earlyUnstakePenalty),
    netPrincipalIfEarlyUnstake: ethers.formatEther(netPrincipalIfEarlyUnstake),
    roi: Number(roi) / 100, // as percentage
    projectedRewardsToMaturity: ethers.formatEther(projectedRewardsToMaturity),
    totalProjectedValue: ethers.formatEther(totalValue + projectedRewardsToMaturity)
  };
}
```

---

#### B. Historical Performance

**Purpose**: Track user's performance over time

**Off-Chain Calculations (from events)**:
```javascript
async function calculateHistoricalPerformance(userAddress, poolId, startBlock, endBlock) {
  // Fetch all relevant events
  const stakedEvents = await poolManager.queryFilter(
    poolManager.filters.BoughtAndStaked(poolId, userAddress),
    startBlock,
    endBlock
  );
  
  const unstakedEvents = await poolManager.queryFilter(
    poolManager.filters.Unstaked(poolId, userAddress),
    startBlock,
    endBlock
  );
  
  const claimEvents = await poolManager.queryFilter(
    poolManager.filters.RewardsClaimed(poolId, userAddress),
    startBlock,
    endBlock
  );
  
  // Calculate totals
  let totalStaked = 0n;
  let totalUnstaked = 0n;
  let totalRewardsClaimed = 0n;
  let totalPenaltiesPaid = 0n;
  
  for (const event of stakedEvents) {
    totalStaked += event.args.ecmAmount;
  }
  
  for (const event of unstakedEvents) {
    totalUnstaked += event.args.principalReturned;
    totalRewardsClaimed += event.args.rewardsPaid;
  }
  
  for (const event of claimEvents) {
    totalRewardsClaimed += event.args.amount;
  }
  
  // Calculate net position
  const netStaked = totalStaked - totalUnstaked;
  const netProfit = totalRewardsClaimed - totalPenaltiesPaid;
  const overallROI = totalStaked > 0n 
    ? (netProfit * 10000n) / totalStaked 
    : 0n;
  
  return {
    totalStaked: ethers.formatEther(totalStaked),
    totalUnstaked: ethers.formatEther(totalUnstaked),
    totalRewardsClaimed: ethers.formatEther(totalRewardsClaimed),
    totalPenaltiesPaid: ethers.formatEther(totalPenaltiesPaid),
    netStaked: ethers.formatEther(netStaked),
    netProfit: ethers.formatEther(netProfit),
    overallROI: Number(overallROI) / 100, // as percentage
    numberOfStakes: stakedEvents.length,
    numberOfUnstakes: unstakedEvents.length,
    numberOfClaims: claimEvents.length
  };
}
```

---

### 6. Liquidity Tracking

#### A. Pool-to-Uniswap Flow

**Purpose**: Monitor liquidity additions and efficiency

**Off-Chain Calculations**:
```javascript
async function trackLiquidityFlow(poolId, startBlock, endBlock) {
  // Fetch transfer events
  const transferEvents = await poolManager.queryFilter(
    poolManager.filters.LiquidityTransferToManager(poolId),
    startBlock,
    endBlock
  );
  
  const addedEvents = await poolManager.queryFilter(
    poolManager.filters.LiquidityAddedToUniswap(poolId),
    startBlock,
    endBlock
  );
  
  // Calculate totals
  let totalTransferred = { ecm: 0n, usdt: 0n };
  let totalAdded = { ecm: 0n, usdt: 0n };
  
  for (const event of transferEvents) {
    totalTransferred.ecm += event.args.ecmAmount;
    totalTransferred.usdt += event.args.usdtAmount;
  }
  
  for (const event of addedEvents) {
    totalAdded.ecm += event.args.ecmAmount;
    totalAdded.usdt += event.args.usdtAmount;
  }
  
  // Calculate efficiency
  const ecmEfficiency = totalTransferred.ecm > 0n 
    ? (totalAdded.ecm * 100n) / totalTransferred.ecm 
    : 0n;
  const usdtEfficiency = totalTransferred.usdt > 0n 
    ? (totalAdded.usdt * 100n) / totalTransferred.usdt 
    : 0n;
  
  // Calculate average delay
  const avgDelay = transferEvents.length > 0 && addedEvents.length > 0
    ? calculateAverageDelay(transferEvents, addedEvents)
    : 0;
  
  return {
    totalTransferred: {
      ecm: ethers.formatEther(totalTransferred.ecm),
      usdt: ethers.formatUnits(totalTransferred.usdt, 6)
    },
    totalAdded: {
      ecm: ethers.formatEther(totalAdded.ecm),
      usdt: ethers.formatUnits(totalAdded.usdt, 6)
    },
    efficiency: {
      ecm: Number(ecmEfficiency),
      usdt: Number(usdtEfficiency)
    },
    avgDelayMinutes: avgDelay,
    numberOfTransfers: transferEvents.length,
    numberOfAdditions: addedEvents.length
  };
}
```

---

### 7. Early Unstake Projections

#### A. Penalty Calculator

**Purpose**: Show users penalty cost for early unstaking

**Off-Chain Calculation**:
```javascript
function calculateEarlyUnstakePenalty(userInfo, poolInfo, currentTimestamp) {
  const stakeEndTime = userInfo.stakeStart + userInfo.stakeDuration;
  const isEarly = currentTimestamp < stakeEndTime;
  
  if (!isEarly) {
    return {
      isEarly: false,
      penaltyAmount: 0n,
      netPrincipal: userInfo.staked,
      penaltyPercentage: 0,
      daysUntilMaturity: 0
    };
  }
  
  const penaltyAmount = (userInfo.staked * BigInt(poolInfo.penaltyBps)) / 10000n;
  const netPrincipal = userInfo.staked - penaltyAmount;
  const daysUntilMaturity = Number(stakeEndTime - currentTimestamp) / 86400;
  
  return {
    isEarly: true,
    penaltyAmount: ethers.formatEther(penaltyAmount),
    netPrincipal: ethers.formatEther(netPrincipal),
    penaltyPercentage: poolInfo.penaltyBps / 100, // Convert from bps to percentage
    daysUntilMaturity
  };
}
```

---

## ReferralModule Off-Chain Calculations

### 1. Commission Projections

#### A. Direct Commission Estimator

**Purpose**: Calculate expected direct commission before purchase

**Off-Chain Calculation**:
```javascript
function estimateDirectCommission(stakedAmount, directBps) {
  const BPS_DENOM = 10000;
  return (stakedAmount * BigInt(directBps)) / BigInt(BPS_DENOM);
}

// Example usage
const stakedECM = ethers.parseEther("1000"); // 1000 ECM
const directBps = 500; // 5%
const expectedCommission = estimateDirectCommission(stakedECM, directBps);
// Result: 50 ECM
```

---

#### B. Multi-Level Commission Calculator

**Purpose**: Calculate multi-level commissions based on reward claims

**Off-Chain Calculation**:
```javascript
function calculateMultiLevelCommissions(rewardAmount, levelConfig) {
  // levelConfig: [L1_bps, L2_bps, L3_bps, ...]
  const BPS_DENOM = 10000;
  
  const commissions = [];
  for (let i = 0; i < levelConfig.length; i++) {
    const commission = (rewardAmount * BigInt(levelConfig[i])) / BigInt(BPS_DENOM);
    commissions.push({
      level: i + 1,
      bps: levelConfig[i],
      amount: ethers.formatEther(commission)
    });
  }
  
  const totalCommission = commissions.reduce((sum, c) => sum + BigInt(c.amount), 0n);
  
  return {
    commissions,
    totalCommission: ethers.formatEther(totalCommission),
    totalPercentage: levelConfig.reduce((sum, bps) => sum + bps, 0) / 100
  };
}

// Example
const rewardClaimed = ethers.parseEther("10000"); // 10000 ECM reward
const levelConfig = [500, 300, 200]; // 5%, 3%, 2%
const mlCommissions = calculateMultiLevelCommissions(rewardClaimed, levelConfig);
// L1: 500 ECM, L2: 300 ECM, L3: 200 ECM, Total: 1000 ECM (10%)
```

---

### 2. Referral Network Analytics

#### A. Referral Chain Depth

**Purpose**: Analyze referral tree structure

**Off-Chain Calculation**:
```javascript
async function analyzeReferralChain(buyerAddress, referralModule, maxDepth = 10) {
  const chain = await referralModule.getReferralChain(buyerAddress, maxDepth);
  
  // Filter out zero addresses
  const activeChain = chain.filter(addr => addr !== ethers.ZeroAddress);
  
  return {
    depth: activeChain.length,
    chain: activeChain,
    hasFullChain: activeChain.length === maxDepth,
    topReferrer: activeChain[activeChain.length - 1] || ethers.ZeroAddress
  };
}
```

---

#### B. Referrer Performance Metrics

**Purpose**: Calculate referrer's total earnings and network size

**Off-Chain Calculation (from events)**:
```javascript
async function calculateReferrerMetrics(referrerAddress, referralModule, startBlock, endBlock) {
  // Fetch direct commission events
  const directEvents = await referralModule.queryFilter(
    referralModule.filters.DirectCommissionPaid(referrerAddress),
    startBlock,
    endBlock
  );
  
  const accrualEvents = await referralModule.queryFilter(
    referralModule.filters.DirectCommissionAccrued(referrerAddress),
    startBlock,
    endBlock
  );
  
  // Fetch multi-level claim events
  const mlClaimEvents = await referralModule.queryFilter(
    referralModule.filters.ReferralPayoutClaimed(null, referrerAddress),
    startBlock,
    endBlock
  );
  
  // Calculate totals
  let totalDirectCommissions = 0n;
  let totalMultiLevelCommissions = 0n;
  let uniqueReferrals = new Set();
  
  for (const event of directEvents) {
    totalDirectCommissions += event.args.amount;
    uniqueReferrals.add(event.args.buyer);
  }
  
  for (const event of accrualEvents) {
    totalDirectCommissions += event.args.amount;
    uniqueReferrals.add(event.args.buyer);
  }
  
  for (const event of mlClaimEvents) {
    totalMultiLevelCommissions += event.args.amount;
  }
  
  // Get current accrued balance
  const currentAccrued = await referralModule.getDirectAccrual(referrerAddress);
  
  return {
    totalDirectCommissions: ethers.formatEther(totalDirectCommissions),
    totalMultiLevelCommissions: ethers.formatEther(totalMultiLevelCommissions),
    totalEarnings: ethers.formatEther(totalDirectCommissions + totalMultiLevelCommissions),
    currentAccrued: ethers.formatEther(currentAccrued),
    uniqueReferrals: uniqueReferrals.size,
    numberOfDirectPurchases: directEvents.length + accrualEvents.length,
    numberOfMLClaims: mlClaimEvents.length
  };
}
```

---

### 3. Multi-Level Commission Distribution

#### A. Merkle Tree Construction (Off-Chain Engine)

**Purpose**: Build Merkle tree for multi-level commission distribution

**Off-Chain Process**:
```javascript
import { MerkleTree } from 'merkletreejs';
import { keccak256 } from 'ethers';

function buildCommissionMerkleTree(commissionData) {
  // commissionData: [{ address, amount }, ...]
  
  // Create leaves: hash(address, amount)
  const leaves = commissionData.map(({ address, amount }) => {
    return ethers.solidityPackedKeccak256(
      ['address', 'uint256'],
      [address, amount]
    );
  });
  
  // Build Merkle tree
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const root = tree.getHexRoot();
  
  // Generate proofs for each address
  const proofs = {};
  for (let i = 0; i < commissionData.length; i++) {
    const leaf = leaves[i];
    const proof = tree.getHexProof(leaf);
    proofs[commissionData[i].address] = proof;
  }
  
  return {
    root,
    proofs,
    totalAmount: commissionData.reduce((sum, { amount }) => sum + amount, 0n)
  };
}

// Example usage
const epoch1Commissions = [
  { address: '0xReferrer1...', amount: ethers.parseEther('100') },
  { address: '0xReferrer2...', amount: ethers.parseEther('50') },
  { address: '0xReferrer3...', amount: ethers.parseEther('75') }
];

const merkleData = buildCommissionMerkleTree(epoch1Commissions);
// Admin submits merkleData.root to ReferralModule.submitReferralPayoutRoot()
// Users use merkleData.proofs[theirAddress] to claim
```

---

## VestingManager Off-Chain Calculations

### 1. Vesting Schedule Projections

#### A. Linear Vesting Calculator

**Purpose**: Calculate vested amount at any point in time

**Off-Chain Calculation**:
```javascript
function calculateVestedAmount(vestingSchedule, currentTimestamp) {
  const { amount, start, duration, claimed } = vestingSchedule;
  
  // Not started yet
  if (currentTimestamp < start) {
    return {
      vested: 0n,
      claimable: 0n,
      percentageVested: 0,
      timeRemaining: Number(start - currentTimestamp),
      isComplete: false
    };
  }
  
  // Fully vested
  if (currentTimestamp >= start + duration) {
    const claimable = amount - claimed;
    return {
      vested: amount,
      claimable,
      percentageVested: 100,
      timeRemaining: 0,
      isComplete: true
    };
  }
  
  // Partially vested (linear)
  const elapsed = currentTimestamp - start;
  const vested = (amount * elapsed) / duration;
  const claimable = vested - claimed;
  const percentageVested = (Number(elapsed) / Number(duration)) * 100;
  const timeRemaining = Number(start + duration - currentTimestamp);
  
  return {
    vested: ethers.formatEther(vested),
    claimable: ethers.formatEther(claimable),
    percentageVested,
    timeRemaining,
    timeRemainingDays: timeRemaining / 86400,
    isComplete: false
  };
}
```

---

#### B. Vesting Schedule Visualizer

**Purpose**: Generate data points for vesting chart

**Off-Chain Calculation**:
```javascript
function generateVestingChart(vestingSchedule, numberOfPoints = 100) {
  const { amount, start, duration } = vestingSchedule;
  const points = [];
  
  const interval = duration / BigInt(numberOfPoints - 1);
  
  for (let i = 0; i < numberOfPoints; i++) {
    const timestamp = start + (interval * BigInt(i));
    const elapsed = timestamp - start;
    const vested = (amount * elapsed) / duration;
    
    points.push({
      timestamp: Number(timestamp),
      date: new Date(Number(timestamp) * 1000).toISOString(),
      vested: ethers.formatEther(vested),
      percentage: (Number(elapsed) / Number(duration)) * 100
    });
  }
  
  // Add final point
  points.push({
    timestamp: Number(start + duration),
    date: new Date(Number(start + duration) * 1000).toISOString(),
    vested: ethers.formatEther(amount),
    percentage: 100
  });
  
  return points;
}
```

---

### 2. Portfolio Vesting Analytics

#### A. Multi-Schedule Aggregator

**Purpose**: Combine multiple vesting schedules into portfolio view

**Off-Chain Calculation**:
```javascript
async function aggregateUserVestingPortfolio(userAddress, vestingManager, currentTimestamp) {
  const vestingIds = await vestingManager.getUserVestingIds(userAddress);
  
  let totalVesting = 0n;
  let totalVested = 0n;
  let totalClaimable = 0n;
  let totalClaimed = 0n;
  
  const schedules = [];
  
  for (const vestingId of vestingIds) {
    const schedule = await vestingManager.getVestingInfo(vestingId);
    const vestedData = calculateVestedAmount(schedule, currentTimestamp);
    
    totalVesting += schedule.amount;
    totalVested += BigInt(vestedData.vested);
    totalClaimable += BigInt(vestedData.claimable);
    totalClaimed += schedule.claimed;
    
    schedules.push({
      vestingId: Number(vestingId),
      poolId: Number(schedule.poolId),
      totalAmount: ethers.formatEther(schedule.amount),
      start: Number(schedule.start),
      duration: Number(schedule.duration),
      claimed: ethers.formatEther(schedule.claimed),
      ...vestedData,
      revoked: schedule.revoked
    });
  }
  
  return {
    numberOfSchedules: vestingIds.length,
    totalVesting: ethers.formatEther(totalVesting),
    totalVested: ethers.formatEther(totalVested),
    totalClaimable: ethers.formatEther(totalClaimable),
    totalClaimed: ethers.formatEther(totalClaimed),
    percentageVested: totalVesting > 0n 
      ? (Number(totalVested) / Number(totalVesting)) * 100 
      : 0,
    schedules
  };
}
```

---

## Cross-Contract Analytics

### 1. Complete User Financial View

**Purpose**: Unified dashboard showing all user's positions

**Off-Chain Calculation**:
```javascript
async function getUserCompleteFinancials(userAddress, poolId, currentTimestamp) {
  // PoolManager data
  const poolInfo = await poolManager.getPoolInfo(poolId);
  const userInfo = await poolManager.getUserInfo(poolId, userAddress);
  const position = calculateUserPosition(poolInfo, userInfo, currentTimestamp);
  
  // ReferralModule data
  const referralMetrics = await calculateReferrerMetrics(userAddress, referralModule, 0, 'latest');
  const directAccrued = await referralModule.getDirectAccrual(userAddress);
  
  // VestingManager data
  const vestingPortfolio = await aggregateUserVestingPortfolio(userAddress, vestingManager, currentTimestamp);
  
  // Aggregate totals
  const totalAssets = 
    BigInt(position.totalValue) + 
    BigInt(vestingPortfolio.totalVesting) + 
    BigInt(referralMetrics.currentAccrued);
  
  const totalClaimable = 
    BigInt(position.pendingRewards) + 
    BigInt(vestingPortfolio.totalClaimable) + 
    directAccrued;
  
  return {
    staking: position,
    referrals: {
      ...referralMetrics,
      directAccrued: ethers.formatEther(directAccrued)
    },
    vesting: vestingPortfolio,
    summary: {
      totalAssets: ethers.formatEther(totalAssets),
      totalClaimable: ethers.formatEther(totalClaimable),
      stakedPercentage: (BigInt(position.staked) * 100n) / totalAssets,
      vestingPercentage: (BigInt(vestingPortfolio.totalVesting) * 100n) / totalAssets,
      referralPercentage: (BigInt(referralMetrics.totalEarnings) * 100n) / totalAssets
    }
  };
}
```

---

### 2. System-Wide Metrics

#### A. Platform Health Dashboard

**Purpose**: Monitor overall platform performance

**Off-Chain Calculation**:
```javascript
async function calculatePlatformMetrics(startBlock, endBlock) {
  const poolCount = await poolManager.poolCount();
  
  let totalStaked = 0n;
  let totalRewardsPaid = 0n;
  let totalCollectedUSDT = 0n;
  let totalUniqueStakers = 0;
  let totalPenalties = 0n;
  
  for (let i = 0; i < poolCount; i++) {
    const pool = await poolManager.getPoolInfo(i);
    
    totalStaked += pool.totalStaked;
    totalRewardsPaid += pool.rewardsPaid;
    totalCollectedUSDT += pool.collectedUSDT;
    totalUniqueStakers += Number(pool.totalUniqueStakers);
    totalPenalties += pool.totalPenaltiesCollected;
  }
  
  // Referral system metrics
  const totalDirectPaid = await referralModule.totalDirectPaid();
  const totalMultiLevelPaid = await referralModule.totalMultiLevelPaid();
  
  // Vesting system metrics
  const vestingStats = await vestingManager.getTokenStats(ecmToken.address);
  
  return {
    pools: {
      count: Number(poolCount),
      totalStaked: ethers.formatEther(totalStaked),
      totalRewardsPaid: ethers.formatEther(totalRewardsPaid),
      totalCollectedUSDT: ethers.formatUnits(totalCollectedUSDT, 6),
      totalUniqueStakers,
      totalPenalties: ethers.formatEther(totalPenalties)
    },
    referrals: {
      totalDirectPaid: ethers.formatEther(totalDirectPaid),
      totalMultiLevelPaid: ethers.formatEther(totalMultiLevelPaid),
      totalCommissions: ethers.formatEther(totalDirectPaid + totalMultiLevelPaid)
    },
    vesting: {
      totalVested: ethers.formatEther(vestingStats.totalVested),
      totalClaimed: ethers.formatEther(vestingStats.totalClaimed),
      pendingVesting: ethers.formatEther(vestingStats.totalVested - vestingStats.totalClaimed)
    },
    overallMetrics: {
      totalValueLocked: ethers.formatEther(totalStaked),
      totalDistributed: ethers.formatEther(totalRewardsPaid + totalDirectPaid + totalMultiLevelPaid),
      averageStakePerUser: totalUniqueStakers > 0 
        ? ethers.formatEther(totalStaked / BigInt(totalUniqueStakers)) 
        : '0'
    }
  };
}
```

---

## Implementation Examples

### Example 1: Real-Time Dashboard

```javascript
// Dashboard update loop
async function updateDashboard(userAddress, poolId) {
  const currentTimestamp = Math.floor(Date.now() / 1000);
  
  // Get all user data
  const financials = await getUserCompleteFinancials(userAddress, poolId, currentTimestamp);
  
  // Update UI
  updateStakingSection(financials.staking);
  updateReferralSection(financials.referrals);
  updateVestingSection(financials.vesting);
  updateSummary(financials.summary);
  
  // Schedule next update
  setTimeout(() => updateDashboard(userAddress, poolId), 10000); // Update every 10s
}
```

### Example 2: Investment Calculator

```javascript
// Help users decide stake amount and duration
function investmentCalculator(stakeAmount, duration, poolInfo) {
  const currentTimestamp = Math.floor(Date.now() / 1000);
  
  // Calculate expected returns
  const expectedRewards = projectRewardsLinear(
    stakeAmount,
    poolInfo.totalStaked + stakeAmount, // After user stakes
    poolInfo.rewardRatePerSecond,
    duration
  );
  
  // Calculate ROI
  const roi = (expectedRewards * 10000n) / stakeAmount;
  
  // Calculate APR
  const SECONDS_PER_YEAR = 31557600;
  const annualizedRewards = (expectedRewards * BigInt(SECONDS_PER_YEAR)) / BigInt(duration);
  const apr = (annualizedRewards * 100n) / stakeAmount;
  
  return {
    stakeAmount: ethers.formatEther(stakeAmount),
    duration: duration / 86400, // days
    expectedRewards: ethers.formatEther(expectedRewards),
    totalReturn: ethers.formatEther(stakeAmount + expectedRewards),
    roi: Number(roi) / 100, // percentage
    apr: Number(apr) // percentage
  };
}
```

### Example 3: Alert System

```javascript
// Monitor and send alerts
async function monitorUserPosition(userAddress, poolId) {
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const poolInfo = await poolManager.getPoolInfo(poolId);
  const userInfo = await poolManager.getUserInfo(poolId, userAddress);
  
  // Check if stake is maturing soon
  const stakeEndTime = userInfo.stakeStart + userInfo.stakeDuration;
  const daysUntilMaturity = (stakeEndTime - currentTimestamp) / 86400;
  
  if (daysUntilMaturity <= 3 && daysUntilMaturity > 0) {
    sendAlert(userAddress, `Your stake matures in ${daysUntilMaturity.toFixed(1)} days!`);
  }
  
  // Check if rewards are claimable
  const pending = calculatePendingRewards(poolInfo, userInfo, currentTimestamp);
  const threshold = ethers.parseEther("100"); // 100 ECM
  
  if (pending > threshold) {
    sendAlert(userAddress, `You have ${ethers.formatEther(pending)} ECM rewards to claim!`);
  }
  
  // Check vesting schedules
  const vestingPortfolio = await aggregateUserVestingPortfolio(userAddress, vestingManager, currentTimestamp);
  const claimableThreshold = ethers.parseEther("50");
  
  if (BigInt(vestingPortfolio.totalClaimable) > claimableThreshold) {
    sendAlert(userAddress, `You have ${vestingPortfolio.totalClaimable} vested ECM ready to claim!`);
  }
}
```

---

## Best Practices

### 1. Caching Strategy
- Cache pool info for 1 minute (rarely changes)
- Recalculate user-specific data on each request (real-time accuracy)
- Invalidate cache on relevant events

### 2. Batch Queries
- Use multicall for fetching multiple pool/user states
- Batch event queries across multiple blocks

### 3. Error Handling
- Handle division by zero (totalStaked === 0)
- Check for expired reward schedules
- Validate timestamp ranges

### 4. Precision
- Use BigInt for all calculations
- Convert to number/string only for display
- Apply rounding only at final display step

### 5. Performance Optimization
- Pre-calculate constants (PRECISION, time conversions)
- Memoize expensive calculations
- Use indexed events for historical data

---

