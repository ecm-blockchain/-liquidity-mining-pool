# Frontend Integration Guide: StakingPool (ethers v6 + TS/JS)

This guide explains how to integrate the StakingPool smart contract into a web frontend. It is derived from the contract (`contracts/StakingPool.sol`) and end-to-end tests (`test/stakingPool.spec.ts`). It covers pool admin and user flows, events, error handling, timing, and fee-on-transfer behavior.

---

## 📋 Table of Contents

1. Prerequisites
2. Contract overview
   - Pool Structure & Lifecycle
   - Participants & Roles
   - Key Mechanisms
   - Visual Pool Lifecycle
3. Getting a contract instance
4. Core data structures and read APIs
5. Pool admin flows (owner of a pool)
   - Admin Journey Overview
   - Create pool (addPool)
   - Add extra rewards (addPoolReward)
   - Stop rewards early (stopReward)
   - Set pool stake limit (setPoolStakeLimit)
   - Recover rewards from empty pools
6. User flows (staking, withdrawing, rewards)
   - User Journey Overview
   - Deposit (stake)
   - Withdraw (and claim)
   - Claim only
   - Emergency withdraw
7. Global admin flows (contract owner)
8. Events and subscriptions
9. Error handling (custom errors)
10. Timing and reward math notes
    - Linear Reward Distribution
    - Visual Reward Accrual
    - Key Reward Functions
    - User Reward Accounting
11. Fee-on-transfer tokens behavior
12. Example UI patterns and integration scenarios
    - Basic User Actions
    - Admin Actions
    - Complex Integration Scenarios
13. Testing your integration

---

## 1) Prerequisites

- ethers v6
- Deployed StakingPool address and ABI (from Hardhat artifacts or TypeChain)
- ERC20 token ABIs for staking and reward tokens
- A connected signer for state-changing operations

Optional libs: wagmi/viem, framework (React/Vue), and a time helper for UI.

---

## 2) Contract overview

StakingPool supports multiple independent pools with linear rewards over time. Think of it as a platform where multiple farming/staking campaigns can coexist independently.

### Pool Structure & Lifecycle

- A pool is defined by: stakingToken, rewardToken, startTime, endTime, precision, totalReward, owner.
- Each pool has 3 primary phases:
  1. **Setup**: After creation but before startTime, only configuration happens.
  2. **Active**: Between startTime and endTime, deposits are accepted and rewards accrue.
  3. **Ended**: After endTime, no new deposits allowed, but claims/withdrawals continue.

### Participants & Roles

- **Contract Owner**: Platform administrator (deployer by default)
  - Emergency functions: `saveMe` (recover tokens), `updateVersion` (version tracking)
  - Cannot access individual pool funds without pool owner permission

- **Pool Owner**: Campaign administrator (can be different per pool)
  - Can create pools, add rewards, stop early, set stake limits
  - Controls reward distribution policy and pool parameters
  - Can recover tokens from unused pools via `withdrawRewardTokensFromEmptyPool`

- **Users**: Stakers who participate in pools
  - Deposit stakingToken to earn rewardToken
  - Earn rewards proportionally to stake size and duration
  - Can claim, withdraw, or emergency withdraw anytime

### Key Mechanisms

- **Linear Reward Distribution**: Rewards accrue evenly from startTime to endTime
- **Pro-rata Rewards**: Based on user's % of total staked tokens
- **Precision Control**: accTokenPerShare with configurable precision (emitted as 10^precision)
- **Fee-on-transfer Support**: Accounts for tokens that take fees on transfers
- **Safety Features**: Emergency withdrawals, stake limits, and owner recovery functions

Key events: Deposit, Withdraw, Claim, EmergencyWithdraw, PoolCreated, PoolStopped, WithdrawTokensEmptyPool, RewardAdded.

### Visual Pool Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Creation   │     │    Setup    │     │    Active   │     │    Ended    │
│             │────▶│             │────▶│             │────▶│             │
│ addPool()   │     │ Before      │     │ startTime   │     │ After       │
│             │     │ startTime   │     │ to endTime  │     │ endTime     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                           │                    │                   │
                           ▼                    ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
                    │ Admin Can:  │     │ Admin Can:  │     │ Admin Can:  │
                    │             │     │             │     │             │
                    │ setStake    │     │ addReward   │     │ withdraw    │
                    │ Limit       │     │ stopReward  │     │ FromEmpty   │
                    │             │     │ setStake    │     │ Pool        │
                    └─────────────┘     │ Limit       │     └─────────────┘
                                        └─────────────┘
                                              │
                                              ▼
                                        ┌─────────────┐
                                        │ Users Can:  │
                                        │             │
                                        │ deposit     │
                                        │ withdraw    │
                                        │ claimReward │
                                        │ emergency   │
                                        │ Withdraw    │
                                        └─────────────┘
```

---

## 3) Getting a contract instance

```ts
import { ethers } from "ethers";
import StakingPoolAbi from "../artifacts/contracts/StakingPool.sol/StakingPool.json";

export function getStakingPool(address: string, providerOrSigner: ethers.Provider | ethers.Signer) {
  return new ethers.Contract(address, StakingPoolAbi.abi, providerOrSigner);
}
```

Tip: Use a signer for write actions and a provider for reads.

---

## 4) Core data structures and read APIs

- poolInfo(uint256): PoolInfo { stakingToken, rewardToken, lastRewardTimestamp, accTokenPerShare, startTime, endTime, precision, totalStaked, totalReward, owner }
- userInfo(address, uint256): UserInfo { amount, rewardDebt }
- getUserInfo(user, poolId): returns UserInfo
- pendingReward(user, poolId): uint256
- getPools(): PoolInfo[]
- getPoolLength(): uint256

Example reads (ethers v6 BigInt outputs):
```ts
const pool = await stakingPool.poolInfo(0);
const user = await stakingPool.getUserInfo(userAddress, 0);
const pending = await stakingPool.pendingReward(userAddress, 0);
const pools = await stakingPool.getPools();
const total = await stakingPool.getPoolLength();
```

---

## 5) Pool admin flows (owner of a pool)

### Admin Journey Overview

```
┌───────────┐     ┌────────────┐     ┌────────────┐     ┌────────────┐
│  Create   │     │ Configure  │     │  Manage    │     │ Finalize   │
│   Pool    │────▶│  Limits    │────▶│  Rewards   │────▶│   Pool     │
│           │     │            │     │            │     │            │
└───────────┘     └────────────┘     └────────────┘     └────────────┘
      │                  │                  │                  │
      │                  │                  │                  │
      ▼                  ▼                  ▼                  ▼
┌───────────┐     ┌────────────┐     ┌────────────┐     ┌────────────┐
│  addPool  │     │    Set     │     │    Add     │     │   Stop     │
│           │     │   Stake    │     │   Extra    │     │  Reward    │
│           │     │   Limit    │     │  Rewards   │     │            │
└───────────┘     └────────────┘     └────────────┘     └────────────┘
                                                              │
                                                              │
                                                              ▼
                                                        ┌────────────┐
                                                        │ Withdraw   │
                                                        │ From Empty │
                                                        │   Pool     │
                                                        └────────────┘
```

### 5.1 Create pool (addPool)

**Inputs:** stakingToken, rewardToken, startTime, endTime, precision [6..36], totalReward.

**Sequence:**
1. Admin approves rewardToken spending to StakingPool contract
2. Admin calls `addPool` with pool parameters
3. Contract validates all parameters (time, precision, amounts)
4. Contract transfers rewardToken from admin
5. Contract stores new pool in poolInfo array
6. Contract emits PoolCreated event

**Requirements:**
- startTime < endTime
- startTime and endTime must be in the future
- Duration <= 5 years (157680000 seconds)
- precision between 6 and 36 (controls decimal precision in reward calculation)
- Approve StakingPool to spend `totalReward` of rewardToken beforehand
- totalReward > 0

**State Changes:**
- New pool added to poolInfo array
- poolVersion mapping updated for new pool

**Emits:** PoolCreated(stakingToken, rewardToken, startTime, endTime, 10^precision, depositedRewardAmount)

**Note:** last arg is the actual transferred amount (equals totalReward for standard ERC20).

```ts
// approve reward tokens
await rewardToken.connect(admin).approve(stakingPool.target, totalReward);
// create pool
await stakingPool.connect(admin).addPool(stakingToken.target, rewardToken.target, startTs, endTs, precision, totalReward);
```

**Choosing Parameters:**
- stakingToken: The token users will deposit (e.g., LP token, governance token)
- rewardToken: The token used as rewards (e.g., project token, governance token)
- precision: Higher values allow for more fractional rewards but use more gas
- totalReward: Total amount to distribute over the pool's lifetime
- startTime/endTime: Define the reward distribution period

**Common reverts:** RewardAmountIsZero, RewardsInPast, InvalidPrecision, InvalidStartAndEndDates, ERC20InsufficientAllowance (from token).

### 5.2 Add extra rewards (addPoolReward)

**Inputs:** poolId, additionalRewardAmount.

**Sequence:**
1. Admin approves rewardToken spending to contract
2. Admin calls `addPoolReward`
3. Contract validates conditions (owner, pool active, time remaining)
4. Contract calls `updatePool` to synchronize rewards
5. Contract calculates usable portion of additional rewards
6. Contract transfers rewardToken from admin
7. Contract updates totalReward
8. Contract emits RewardAdded event

**Rules:**
- Only pool owner can call
- Pool must not have ended
- At least 1 hour must remain in pool duration (InsufficientRemainingTime)
- The contract transfers only the usable portion for the remaining time:
  ```
  usableNewReward = timeLeft * additionalRewardAmount / totalDuration
  ```

**State Changes:**
- pool.totalReward += additionalRewardAmount (virtual increase)
- Actual transferred amount is the usable portion

**Emits:** RewardAdded(poolId, usableNewReward, rewardToken)

**Reward Rate Impact:**
Adding rewards increases the effective reward rate for the remaining duration. The new rate becomes:
```
newRate = (oldTotalReward + additionalRewardAmount) / totalDuration
```
But only for the remaining time.

**Common reverts:** NotPoolOwner, RewardAmountIsZero, PoolEnded, InsufficientRemainingTime, ERC20InsufficientAllowance (from token), InsufficientTransferredAmount (safety check).

### 5.3 Stop rewards early (stopReward)

**Sequence:**
1. Admin calls `stopReward(poolId)`
2. Contract calls `updatePool` to synchronize rewards
3. Contract validates conditions (owner, pool active)
4. Contract calculates remaining rewards
5. Contract updates pool parameters (endTime=now, totalReward=0)
6. Contract marks pool as emptied
7. Contract transfers remaining rewards back to pool owner
8. Contract emits PoolStopped event

**Rules:**
- Only pool owner can call
- Pool must be active (not ended)
- Remaining rewards are calculated proportionally:
  ```
  remainingRewards = ((oldEnd - max(now, start)) * totalReward) / (oldEnd - start)
  ```

**State Changes:**
- pool.totalReward = 0
- pool.endTime = block.timestamp
- emptiedPools[poolId] = true

**Emits:** PoolStopped(poolId)

**Implications:**
- No new deposits allowed
- Users can still withdraw and claim earned rewards
- Rewards stop accruing from this point forward

**Common reverts:** NotPoolOwner, PoolEnded, CannotStopRewards (if not enough duration context).

### 5.4 Set pool stake limit (setPoolStakeLimit)

**Sequence:**
1. Admin calls `setPoolStakeLimit(poolId, stakeLimit)`
2. Contract validates conditions (owner, pool active, limit > totalStaked)
3. Contract updates poolStakeLimit mapping

**Rules:**
- Only pool owner can call
- Pool must not have ended
- New limit must be >= current totalStaked

**State Changes:**
- poolStakeLimit[poolId] = stakeLimit

**Use Cases:**
- Control total capital allocation to a specific pool
- Prevent economic attacks through over-concentration
- Phase reward campaigns with increasing limits

**Common reverts:** NotPoolOwner, PoolEnded, InvalidStakeLimit.

### 5.5 Recover rewards from an empty pool (withdrawRewardTokensFromEmptyPool)

**Sequence:**
1. Admin calls `withdrawRewardTokensFromEmptyPool(poolId)`
2. Contract calls `updatePool` to synchronize rewards
3. Contract validates all conditions
4. Contract marks pool as emptied
5. Contract transfers all reward tokens to pool owner
6. Contract emits WithdrawTokensEmptyPool event

**Rules:**
- Only pool owner can call
- Pool must have ended (block.timestamp >= pool.endTime)
- Pool must have never been staked in (accTokenPerShare == 0)
- Pool must not be already emptied

**Use Cases:**
- Recover funds from unused pools
- Close out pools with zero participation

**State Changes:**
- emptiedPools[poolId] = true

**Emits:** WithdrawTokensEmptyPool(poolId)

**Common reverts:** PoolDoesNotExist, PoolAlreadyEmpty, PoolAlreadyStakedIn, CannotClaimBeforePoolEnds, NotPoolOwner.

---

## 6) User flows (staking, withdrawing, rewards)

### User Journey Overview

```
┌───────────┐     ┌────────────┐     ┌────────────┐     ┌────────────┐
│ Discover  │     │  Deposit   │     │   Earn     │     │ Withdraw   │
│ Pools     │────▶│  (Stake)   │────▶│  Rewards   │────▶│  & Claim   │
│           │     │            │     │            │     │            │
└───────────┘     └────────────┘     └────────────┘     └────────────┘
      │                                      │                 │
      │                                      │                 │
      ▼                                      ▼                 ▼
┌───────────┐                         ┌────────────┐    ┌────────────┐
│ View Pool │                         │   Claim    │    │ Emergency  │
│ Details   │                         │  Rewards   │    │ Withdraw   │
│           │                         │  (Only)    │    │            │
└───────────┘                         └────────────┘    └────────────┘
```

### 6.1 Deposit (stake)

**Inputs:** amount, poolId

**Sequence:**
1. User approves stakingToken to StakingPool (`stakingToken.approve(stakingPool.address, amount)`)
2. User calls `deposit(amount, poolId)`
3. Contract updates pool rewards (`updatePool(poolId)`)
4. Contract calculates pending rewards if user already has stake
5. Contract transfers stakingToken from user
6. Contract updates user.amount, user.rewardDebt, and pool.totalStaked
7. Contract emits `Deposit(user, depositAmountReceived, poolId)`

**State Changes:**
- user.amount += depositAmount
- user.rewardDebt = (user.amount * pool.accTokenPerShare) / pool.precision
- pool.totalStaked += depositAmount
- If existing stake, pending rewards stay in rewardCredit

**Rules:**
- Pool must exist and not be ended
- Amount must be > 0
- Stake limit (if set) must not be exceeded
- For fee-on-transfer tokens, the credited deposit equals the actual received amount

**Reverts:** AmountIsZero, PoolDoesNotExist, PoolEnded, MaximumStakeAmountReached (if limit), ERC20 errors (from token).

### 6.2 Withdraw (and optional claim)

**Inputs:** amount, poolId

**Sequence:**
1. User calls `withdraw(amount, poolId)`
2. Contract updates pool rewards (`updatePool(poolId)`)
3. Contract calculates pending rewards
4. Contract updates user position (amount, rewardDebt)
5. Contract transfers stakingToken (withdrawal amount) to user
6. If pending > 0, contract transfers rewardToken to user
7. Contract emits `Withdraw` and possibly `Claim` events

**State Changes:**
- user.amount -= amount
- pool.totalStaked -= amount
- user.rewardDebt = (new user.amount * pool.accTokenPerShare) / pool.precision
- rewardCredit[user][poolId] = 0 if rewards claimed

**Reverts:** AmountIsZero, PoolDoesNotExist, standard underflow if amount > user.amount.

### 6.3 Claim only

**Inputs:** poolId

**Sequence:**
1. User calls `claimReward(poolId)`
2. Contract updates pool rewards (`updatePool(poolId)`)
3. Contract calculates pending rewards 
4. Contract updates user.rewardDebt and resets rewardCredit
5. Contract transfers rewardToken to user
6. Contract emits `Claim(user, amount, poolId)`

**State Changes:**
- user.rewardDebt = (user.amount * pool.accTokenPerShare) / pool.precision
- rewardCredit[user][poolId] = 0

### 6.4 Emergency withdraw

**Inputs:** poolId

**Sequence:**
1. User calls `emergencyWithdraw(poolId)`
2. Contract fetches user stake amount (no reward calculation)
3. Contract resets user position and reduces pool.totalStaked
4. Contract transfers full stakingToken amount to user
5. Contract emits `EmergencyWithdraw(user, amount)`

**State Changes:**
- pool.totalStaked -= user.amount
- user.amount = 0
- user.rewardDebt = 0
- rewardCredit[user][poolId] = 0

**When to use:** When you suspect a bug or issue with reward calculation but want to recover your stake. All accrued rewards will be forfeited.

**Reverts:** AmountIsZero (if user has 0 staked), PoolDoesNotExist.

---

## 7) Global admin flows (contract owner)

### 7.1 Recover arbitrary tokens sent to contract (saveMe)
Only contract owner. Transfers `amount` of `tokenAddress` to owner.

### 7.2 Update contract version (updateVersion)
Only contract owner. Sets `currentVersion` for tracking upgrades/migrations.

---

## 8) Events and subscriptions

Listen and react to:
- PoolCreated(stakingToken, rewardToken, startTime, endTime, precisionScaled, depositedReward)
- RewardAdded(poolId, usableNewReward, rewardToken)
- PoolStopped(poolId)
- Deposit(user, amount, poolId)
- Withdraw(user, amount, poolId)
- Claim(user, amount, poolId)
- EmergencyWithdraw(user, amount)
- WithdrawTokensEmptyPool(poolId)

Example (ethers v6):
```ts
stakingPool.on("Deposit", (user, amount, poolId) => {
  console.log("Deposit", { user, amount: amount.toString(), poolId: Number(poolId) });
});
```

Filter by user or pool to reduce noise.

---

## 9) Error handling (custom errors)

Common custom reverts you should map to human-readable messages:
- NotPoolOwner(expectedOwner, caller)
- RewardAmountIsZero
- AmountIsZero
- PoolEnded(poolId)
- RewardsInPast
- InvalidPrecision
- PoolDoesNotExist(poolId)
- InvalidStartAndEndDates
- CannotStopRewards
- InvalidStakeLimit(totalStaked, stakeLimit)
- MaximumStakeAmountReached(stakeLimit)
- InsufficientTransferredAmount
- InsufficientRemainingTime(timeLeft)
- PoolAlreadyStakedIn(poolId)
- CannotClaimBeforePoolEnds(poolId)
- PoolAlreadyEmpty(poolId)

Plus ERC20 standard errors like ERC20InsufficientAllowance. In ethers v6, inspect `e.shortMessage`, `e.data`, or use `Interface.parseError` against the StakingPool ABI to decode custom errors.

---

## 10) Timing and reward math notes

### Linear Reward Distribution

Rewards accrue linearly between `startTime` and `endTime`. The contract calculates rewards as follows:

```
rewards = ((currentTime - lastUpdateTime) * totalReward) / (endTime - startTime)
```

This means the rate is constant: `totalReward / (endTime - startTime)` tokens per second.

### Visual Reward Accrual

```
TotalReward                                                      ┌─────────
    ^                                                          ╱┘
    │                                                        ╱
    │                                                      ╱
    │                                                    ╱
    │                                                  ╱
    │                                                ╱
    │                                              ╱
    │                                            ╱
    │                                          ╱
    │                                        ╱
    │                                      ╱
    │                                    ╱
    │                                  ╱
    │                                ╱
    │                              ╱
    │                            ╱
    │                          ╱
    │                        ╱
    │                      ╱
    │                    ╱
    │                  ╱
    │                ╱
    │              ╱
    │            ╱
    │          ╱
    │        ╱
    │      ╱
    │    ╱
    │  ╱
    │╱
    └─────────────────────────────────────────────────────────────────────────▶ Time
      startTime                                               endTime
```

### Key Reward Functions

- **updatePool(poolId)**: Called before any state changes (deposits, withdrawals, claims)
  - Updates `accTokenPerShare` = previous + (rewards * precision) / totalStaked
  - Updates `lastRewardTimestamp` to current time

- **pendingReward(user, poolId)**: Read-only calculation of pending rewards
  - Formula: `(user.amount * accTokenPerShare) / precision - user.rewardDebt + rewardCredit`
  - Does a simulated `updatePool` calculation first to get current rewards

### User Reward Accounting

When a user deposits:
```
user.rewardDebt = (user.amount * pool.accTokenPerShare) / pool.precision
```

When rewards are claimed or withdrawn:
```
pending = (user.amount * pool.accTokenPerShare) / pool.precision - user.rewardDebt + rewardCredit
user.rewardDebt = (user.amount * pool.accTokenPerShare) / pool.precision
rewardCredit = 0
```

### Precision Handling

- `precision` parameter controls decimal handling (between 6 and 36)
- Scaled as 10^precision in calculations and event emissions
- Higher precision = more accurate reward distribution but higher gas costs
- Recommended: 10-18 for most use cases

### Adding Extra Rewards

When adding extra rewards with `addPoolReward`:

```
useableNewReward = timeLeft * additionalRewardAmount / totalDuration
```

Only the usable portion is transferred and used for calculation; the virtual totalReward is updated by the full amount.

### Considerations for Frontend Developers

- Time-based calculations have slight rounding differences; use tolerances in UI comparisons
- Handle edge cases gracefully:
  - Zero totalStaked periods (no rewards accrue)
  - Before pool start (no rewards accrue)
  - After pool end (rewards calculation stops)
- Display estimated APR/APY based on current rate and totalStaked

---

## 11) Fee-on-transfer tokens behavior

Deposits use `transferFunds` to measure actual tokens received by the contract. If the staking token charges a fee-on-transfer:
- The user’s credited stake equals the net amount received (may be less than requested amount).
- The `Deposit` event’s `amount` is the net amount.

Your UI should read the `Deposit` event or `getUserInfo` after the transaction to display the final staked amount.

---

## 12) Example UI patterns and integration scenarios

### Basic User Action Patterns

#### Approve + Deposit
```ts
// One-time approval (can be max uint256 for infinite approval)
await stakingToken.connect(user).approve(stakingPool.target, amount);
// Deposit tokens to start earning rewards
await stakingPool.connect(user).deposit(amount, poolId);
```

#### Withdraw + auto-claim
```ts
// Withdraw staked tokens and automatically claim any pending rewards
await stakingPool.connect(user).withdraw(amount, poolId);
```

#### Claim only
```ts
// Claim rewards without withdrawing stake
await stakingPool.connect(user).claimReward(poolId);
```

#### Emergency withdraw
```ts
// Withdraw staked tokens without claiming rewards (in case of emergency)
await stakingPool.connect(user).emergencyWithdraw(poolId);
```

### Admin Action Patterns

#### Create pool (admin)
```ts
// Approve reward token transfer
await rewardToken.connect(admin).approve(stakingPool.target, totalReward);
// Create new staking pool
await stakingPool.connect(admin).addPool(
  stakingToken.target,  // Token users will stake
  rewardToken.target,   // Token given as rewards
  startTs,              // Pool start timestamp
  endTs,                // Pool end timestamp
  precision,            // Precision factor (usually 10-18)
  totalReward           // Total rewards for the pool duration
);
```

#### Add extra rewards (admin)
```ts
// Approve additional rewards
await rewardToken.connect(admin).approve(stakingPool.target, extraAmount);
// Add more rewards to an existing pool
await stakingPool.connect(admin).addPoolReward(poolId, extraAmount);
```

#### Stop rewards early (admin)
```ts
// End the pool early and return remaining rewards to admin
await stakingPool.connect(admin).stopReward(poolId);
```

#### Set stake limit (admin)
```ts
// Set maximum total stake for the pool
await stakingPool.connect(admin).setPoolStakeLimit(poolId, stakeLimit);
```

#### Recover empty pool rewards (admin)
```ts
// Recover funds from unused pool (only if no staking occurred)
await stakingPool.connect(admin).withdrawRewardTokensFromEmptyPool(poolId);
```

#### Contract owner utilities
```ts
// Recover any tokens accidentally sent to contract
await stakingPool.connect(owner).saveMe(tokenAddress, amount);
// Update contract version (for tracking/migration)
await stakingPool.connect(owner).updateVersion(2n);
```

### Complex Integration Scenarios

#### Complete User Dashboard

```ts
// Get all available pools
const poolCount = await stakingPool.getPoolLength();
const pools = [];

// Load pool data
for (let i = 0; i < poolCount; i++) {
  const poolInfo = await stakingPool.poolInfo(i);
  const userInfo = await stakingPool.getUserInfo(userAddress, i);
  const pendingRewards = await stakingPool.pendingReward(userAddress, i);
  const stakeLimit = await stakingPool.poolStakeLimit(i);
  
  // Format data for UI
  pools.push({
    poolId: i,
    stakingToken: poolInfo.stakingToken,
    rewardToken: poolInfo.rewardToken,
    totalStaked: formatUnits(poolInfo.totalStaked, stakingTokenDecimals),
    userStaked: formatUnits(userInfo.amount, stakingTokenDecimals),
    pendingRewards: formatUnits(pendingRewards, rewardTokenDecimals),
    startTime: new Date(Number(poolInfo.startTime) * 1000),
    endTime: new Date(Number(poolInfo.endTime) * 1000),
    isActive: poolInfo.endTime > Math.floor(Date.now() / 1000),
    stakeLimit: stakeLimit > 0 ? formatUnits(stakeLimit, stakingTokenDecimals) : 'Unlimited',
    remainingCapacity: stakeLimit > 0 
      ? formatUnits(stakeLimit - poolInfo.totalStaked, stakingTokenDecimals) 
      : 'Unlimited',
  });
}
```

#### Real-time Reward Monitoring

```ts
// Set up listeners for key events
stakingPool.on("Deposit", (user, amount, poolId) => {
  if (user.toLowerCase() === userAddress.toLowerCase()) {
    updateUserStakeDisplay(poolId, amount);
    showNotification(`Stake successful: ${formatUnits(amount, decimals)} tokens`);
  }
  // Always update pool total stats
  updatePoolTotalStake(poolId);
});

stakingPool.on("Claim", (user, amount, poolId) => {
  if (user.toLowerCase() === userAddress.toLowerCase()) {
    updateRewardsDisplay(poolId, 0); // Reset pending rewards
    showNotification(`Rewards claimed: ${formatUnits(amount, decimals)} tokens`);
  }
});

// Function to periodically update pending rewards display
function startRewardTracker() {
  return setInterval(async () => {
    for (const pool of activeUserPools) {
      const pending = await stakingPool.pendingReward(userAddress, pool.poolId);
      updateRewardsDisplay(pool.poolId, pending);
    }
  }, 15000); // Update every 15 seconds
}
```

#### Admin Pool Management Dashboard

```ts
// Create a new pool
async function createPool(formData) {
  try {
    setLoading(true);
    const { stakingToken, rewardToken, startDate, duration, totalReward, precision } = formData;
    
    // Convert dates to timestamps
    const startTimestamp = Math.floor(startDate.getTime() / 1000);
    const endTimestamp = startTimestamp + (duration * 24 * 60 * 60); // duration in days
    
    // Format amounts with proper decimals
    const formattedReward = parseUnits(totalReward.toString(), rewardTokenDecimals);
    
    // Check if current time + 5 min < startTime to give buffer for transaction
    if (Math.floor(Date.now() / 1000) + 300 >= startTimestamp) {
      throw new Error("Start time must be at least 5 minutes in the future");
    }
    
    // First approve tokens
    const approveTx = await rewardTokenContract.approve(stakingPool.target, formattedReward);
    await approveTx.wait();
    
    // Then create pool
    const tx = await stakingPool.addPool(
      stakingToken, 
      rewardToken,
      startTimestamp,
      endTimestamp,
      precision || 18, // Default to 18 if not specified
      formattedReward
    );
    
    const receipt = await tx.wait();
    
    // Find the PoolCreated event to get the pool ID
    const event = receipt.logs
      .map(log => { try { return stakingPool.interface.parseLog(log); } catch (e) { return null; }})
      .filter(parsed => parsed && parsed.name === 'PoolCreated')[0];
      
    // Show success and return the new pool ID
    showNotification("Pool created successfully!");
    return receipt;
  } catch (error) {
    handleError(error);
    throw error;
  } finally {
    setLoading(false);
  }
}
```

#### APR/APY Calculator for Pools

```ts
// Calculate and display APR for a staking pool
async function calculateAPR(poolId) {
  const pool = await stakingPool.poolInfo(poolId);
  
  // Get token prices from oracle or API
  const stakingTokenPrice = await getTokenPrice(pool.stakingToken);
  const rewardTokenPrice = await getTokenPrice(pool.rewardToken);
  
  // Calculate time remaining in seconds
  const now = Math.floor(Date.now() / 1000);
  const timeRemaining = Math.max(0, Number(pool.endTime) - now);
  const totalDuration = Number(pool.endTime) - Number(pool.startTime);
  
  // Calculate rewards per second in USD
  const totalRewardValue = Number(formatUnits(pool.totalReward, rewardTokenDecimals)) * rewardTokenPrice;
  const rewardPerSecond = pool.totalReward / totalDuration;
  const rewardPerSecondUSD = Number(formatUnits(rewardPerSecond, rewardTokenDecimals)) * rewardTokenPrice;
  
  // Calculate total staked value in USD
  const totalStakedUSD = Number(formatUnits(pool.totalStaked, stakingTokenDecimals)) * stakingTokenPrice;
  
  if (totalStakedUSD === 0) return { apr: 0, apy: 0 };
  
  // APR = (annual reward value / total staked value) * 100
  const annualRewardUSD = rewardPerSecondUSD * 31536000; // seconds in a year
  const apr = (annualRewardUSD / totalStakedUSD) * 100;
  
  // APY calculation (compounded daily) - only applies if rewards can be restaked
  const apy = (Math.pow(1 + (apr / 36500), 365) - 1) * 100;
  
  return { apr, apy, remainingDays: timeRemaining / 86400 };
}
```

---

## 13) Testing your integration

Reference behaviors verified in the test suite (`test/stakingPool.spec.ts`):
- Pool creation validation and PoolCreated event
- addPoolReward constraints and RewardAdded event
- stopReward transfers remaining rewards and PoolStopped event
- setPoolStakeLimit access and constraints
- User deposit/withdraw/claim flows, including proportional rewards and events
- Emergency withdraw flow and event
- Info queries: getUserInfo, getPools, getPoolLength, pendingReward
- Contract owner functions: saveMe, updateVersion
- Edge cases: nonexistent pool IDs, zero amounts, ended pools, stake limits, and time-based conditions

Use these as acceptance criteria when wiring your frontend.

---

## 11. Best Practices

### Performance Optimization

1. **Batched Requests**: Use `Promise.all()` for multiple contract calls
2. **Caching**: Cache contract constants and user data
3. **Event Filtering**: Filter events by user address to reduce noise
4. **Lazy Loading**: Load schedule details only when needed

### Security Considerations

1. **Input Validation**: Always validate user inputs before contract calls
2. **Address Validation**: Use `ethers.isAddress()` for address inputs
3. **Amount Validation**: Check against contract limits and user balance
4. **Error Handling**: Parse and display user-friendly error messages
5. **Transaction Confirmation**: Wait for transaction confirmations

### User Experience

1. **Loading States**: Show loading indicators for all async operations
2. **Error Feedback**: Provide clear, actionable error messages
3. **Transaction Status**: Show transaction hashes and confirmation status
4. **Real-time Updates**: Listen to events for real-time UI updates
5. **Responsive Design**: Ensure mobile compatibility

### Code Organization

1. **Composables**: Separate concerns into focused composables
2. **Error Handling**: Centralized error parsing and handling
3. **Type Safety**: Use TypeScript for better development experience
4. **Component Reuse**: Create reusable components for common UI patterns
5. **Testing**: Write comprehensive integration tests

---