# Pool Creation & Configuration Guide

## Pre-Deployment Guide (Pool Creation Prerequisites)

### 1. Prerequisites
- **Admin Wallet**: Secure wallet with sufficient ECM and USDT for allocations
- **Contract Deployment**: PoolManager, LiquidityManager, VestingManager, ReferralModule, ReferralVoucher deployed and verified
- **Token Approvals**: Admin must approve PoolManager to spend ECM and USDT for sale and rewards
- **Uniswap V2 Pair**: ECM/USDT pair deployed and address known
- **Penalty Receiver**: Treasury or burn address for slashed tokens
- **Allowed Stake Durations**: Decide durations (e.g., [30 days, 90 days, 180 days]) - users select from these options
- **Max Duration**: Set maximum allowed staking duration for the pool
- **Vesting Duration**: Set vesting period for rewards (if using vesting)
- **Reward Strategy**: Choose LINEAR, MONTHLY, or WEEKLY, and prepare schedule if needed
- **Referral System**: Configure ReferralModule and ReferralVoucher (if using referrals)

### 2. Pool Creation Steps
1. **Approve ECM for Sale**:
   - `ecm.approve(poolManager.address, saleAmount)`
2. **Approve ECM for Rewards**:
   - `ecm.approve(poolManager.address, rewardAmount)`
3. **Create Pool**:
   - Call `poolManager.createPool(PoolCreateParams)` where params include:
     - `ecm`: ECM token address
     - `usdt`: USDT token address
     - `pair`: Uniswap V2 pair address
     - `penaltyReceiver`: Address to receive slashed tokens
     - `rewardStrategy`: LINEAR, MONTHLY, or WEEKLY
     - `allowedStakeDurations`: Array of allowed durations
     - `maxDuration`: Maximum allowed staking duration
     - `vestingDuration`: Duration for reward vesting (0 = no vesting)
     - `vestRewardsByDefault`: Auto-vest rewards flag
     - `penaltyBps`: Penalty in basis points (0 = use default 2500)
   - Save returned `poolId`
4. **Allocate ECM for Sale**:
   - `poolManager.allocateForSale(poolId, saleAmount)`
5. **Allocate ECM for Rewards**:
   - `poolManager.allocateForRewards(poolId, rewardAmount)`
6. **Configure Reward Strategy**:
   - For LINEAR: `poolManager.setLinearRewardRate(poolId)` - auto-calculates rate
   - For MONTHLY: `poolManager.setMonthlyRewards(poolId, [month1, month2, ...])`
   - For WEEKLY: `poolManager.setWeeklyRewards(poolId, [week1, week2, ...])`
7. **Activate Pool** (pool is active by default after creation):
   - `poolManager.setPoolActive(poolId, true)` (optional - already active)

---

## Post-Deployment Guide (Pool Configuration & Management)

### 1. Post-Deployment Configuration
- **Update Allowed Stake Durations**:
  - `poolManager.setAllowedStakeDurations(poolId, [newDurations])`
- **Change Penalty Settings**:
  - `poolManager.setPenaltyConfig(poolId, newPenaltyBps, newPenaltyReceiver)`
- **Update Vesting Settings**:
  - `poolManager.setVestingConfig(poolId, newVestingDuration, vestByDefault)`
- **Switch Reward Strategy**:
  - For LINEAR: `poolManager.setLinearRewardRate(poolId)` - auto-calculates optimal rate
  - For MONTHLY: `poolManager.setMonthlyRewards(poolId, [newSchedule])`
  - For WEEKLY: `poolManager.setWeeklyRewards(poolId, [newSchedule])`
- **Add More ECM for Sale/Rewards**:
  - `poolManager.allocateForSale(poolId, additionalAmount)`
  - `poolManager.allocateForRewards(poolId, additionalAmount)`
- **Pause/Unpause Pool**:
  - `poolManager.setPoolActive(poolId, false)` / `true`
- **Emergency Token Recovery**:
  - `poolManager.emergencyRecoverTokens(token, amount, to)` (never touches user stakes)

### 2. Liquidity Management
- **Authorize LiquidityManager**:
  - `poolManager.addAuthorizedLiquidityManager(liquidityManagerAddress)`
- **Transfer to LiquidityManager**:
  - `poolManager.transferToLiquidityManager(poolId, liquidityManager, ecmAmount, usdtAmount)`
  - Note: ECM is transferred from sold/staked pool (up to totalStaked - liquidityPoolOwedECM)
  - USDT is transferred from collectedUSDT
- **Add Liquidity on Uniswap**:
  - `liquidityManager.addLiquidity(ecmAmount, usdtAmount, minEcm, minUsdt, to, deadline)`
  - LiquidityManager calls `poolManager.recordLiquidityAdded(poolId, ecmAmount, usdtAmount)` callback
- **Refill Pool (Return Unused ECM)**:
  - `poolManager.refillPoolManager(poolId, ecmAmount)` - called by authorized LiquidityManager

### 3. VestingManager Operations
- **Set VestingManager Contract**:
  - `poolManager.setVestingManager(vestingManagerAddress)`
- **Create Vesting Schedules**:
  - Handled automatically on reward claim if `vestRewardsByDefault = true`
  - Vesting created via `vestingManager.createVesting(beneficiary, amount, start, duration, token, poolId)`
- **Claim Vested Tokens**:
  - Users call `vestingManager.claimVested(vestingId)` to claim linearly vested rewards

### 4. Referral System Operations
- **Set ReferralVoucher Contract**:
  - `poolManager.setReferralVoucher(referralVoucherAddress)`
- **Set ReferralModule Contract**:
  - `poolManager.setReferralModule(referralModuleAddress)`
  - Note: Must also call `referralVoucher.setReferralModule(referralModuleAddress)` separately (as owner)
- **Issue Vouchers**:
  - Off-chain EIP-712 signing of voucher data (see README)
- **Set Referrer After Purchase**:
  - Users can call `poolManager.setMyReferrer(voucherInput, signature)` one-time only
- **Claim Referral Commissions**:
  - `referralModule.claimReferral(epochId, token, amount, proof)` with Merkle proof

---

## Best Practices & Tips

### For Admins
- Always allocate rewards BEFORE setting reward rates (LINEAR/MONTHLY/WEEKLY)
- For LINEAR strategy: `setLinearRewardRate()` auto-calculates optimal rate from remaining rewards and maxDuration
- Monitor reward depletion: use `calculateRewardDepletionTime()` to track when rewards run out
- Use `getPoolBalanceStatus()` to monitor ECM inventory and detect any deficits
- Authorize LiquidityManager before transferring liquidity: `addAuthorizedLiquidityManager()`
- Never sweep user-staked tokens; only transfer explicitly designated amounts
- Document all configuration changes for auditability

### For Frontend Developers
- Query `allowedStakeDurations` from pool to show valid options
- Check `MIN_PURCHASE_ECM` (500 ECM) before allowing purchase
- Use `estimateECMForUSDT()` to preview purchase amounts
- Use `getRequiredUSDTForExactECM()` for exact ECM purchases
- Call `calculateUnstakePenalty()` before unstake to show penalty preview
- Use `pendingRewards()` to display claimable rewards
- Monitor events for real-time updates
- Handle slippage protection with `maxUsdtAmount` parameter

### For Users
- Understand penalty: Early unstake slashes 25% of principal by default
- Rewards are NEVER slashed, only principal
- Choose stake duration from allowed options (no minimum lock required)
- Minimum purchase: 500 ECM
- Referral can be set during purchase OR one-time after via `setMyReferrer()`
- Vested rewards vest linearly over `vestingDuration` period

### Testing & Validation
- Use test suite to validate all flows before mainnet launch
- Test edge cases: reward depletion, early unstake, liquidity transfers
- Verify Uniswap V2 pair pricing is accurate
- Test referral voucher expiration and revocation
- Validate vesting schedules and claims

---

## View Functions & Analytics

### Pool Information
```typescript
// Get pool details
const pool = await poolManager.getPoolInfo(poolId);
console.log('Allocated for sale:', pool.allocatedForSale);
console.log('Allocated for rewards:', pool.allocatedForRewards);
console.log('Total sold:', pool.sold);
console.log('Total staked:', pool.totalStaked);
console.log('Reward strategy:', pool.rewardStrategy); // 0=LINEAR, 1=MONTHLY, 2=WEEKLY

// Get user info
const user = await poolManager.getUserInfo(poolId, userAddress);
console.log('Staked:', user.staked);
console.log('Pending rewards:', user.pendingRewards);
console.log('Total rewards claimed:', user.totalRewardsClaimed);

// Get comprehensive balance status
const balance = await poolManager.getPoolBalanceStatus(poolId);
console.log('Total allocated:', balance.totalAllocated);
console.log('Currently staked:', balance.currentlyStaked);
console.log('Rewards paid:', balance.rewardsPaid);
console.log('Available in contract:', balance.availableInContract);
console.log('Deficit:', balance.deficit); // Non-zero indicates accounting issue
```

### Analytics & Metrics
```typescript
// Calculate APR (Annual Percentage Rate)
const periodsToProject = ethers.parseEther('1'); // 1 year for LINEAR
// For MONTHLY: periodsToProject = 12 (months)
// For WEEKLY: periodsToProject = 52 (weeks)
const apr = await poolManager.calculateAPR(poolId, periodsToProject);
console.log('APR:', apr.toString(), '%'); // Scaled by 1e18

// Calculate expected rewards for user over duration
const durationSeconds = 90 * 24 * 3600; // 90 days
const expected = await poolManager.calculateExpectedRewards(poolId, userAddress, durationSeconds);
console.log('Expected rewards:', expected.toString());

// Calculate ROI (Return on Investment)
const ecmPriceInUsdt = ethers.parseEther('0.01'); // $0.01 per ECM
const roi = await poolManager.calculateROI(poolId, userAddress, durationSeconds, ecmPriceInUsdt);
console.log('ROI:', roi.toString(), '%'); // Scaled by 1e18

// Calculate TVL (Total Value Locked)
const tvl = await poolManager.calculateTVL(poolId, ecmPriceInUsdt);
console.log('TVL:', tvl.toString()); // In USDT (scaled by 1e6)

// Get pool analytics
const analytics = await poolManager.getPoolAnalytics(poolId, ecmPriceInUsdt);
console.log('Pool age:', analytics.poolAge, 'seconds');
console.log('Unique stakers:', analytics.totalUniqueStakers);
console.log('Total penalties:', analytics.totalPenaltiesCollected);
console.log('Peak staked:', analytics.peakTotalStaked);

// Get user analytics
const userAnalytics = await poolManager.getUserAnalytics(poolId, userAddress);
console.log('Has staked:', userAnalytics.hasStaked);
console.log('First stake:', new Date(userAnalytics.firstStakeTimestamp * 1000));
console.log('Total staked:', userAnalytics.totalStaked);
console.log('Total rewards claimed:', userAnalytics.totalRewardsClaimed);
```

---

## Table of Contents
1. Setup & Connection
2. User Flows (Purchase, Stake, Claim, Unstake)
3. Referral System Integration (EIP-712 Vouchers)
4. Event Subscriptions
5. Off-Chain Calculations (Referral Commissions, Merkle Trees)
6. Vesting Tracking
7. Error Handling
8. Complete Examples (TypeScript/Ethers v6)
9. View Functions & Analytics

---

## 1. Setup & Connection

### Contract Addresses
- PoolManager: `0x...`
- ReferralVoucher: `0x...`
- ReferralModule: `0x...`
- VestingManager: `0x...`
- LiquidityManager: `0x...`

### Key Constants (from PoolManager.sol)
```typescript
const PRECISION = ethers.parseEther('1'); // 1e18
const MIN_PURCHASE_ECM = ethers.parseEther('500'); // 500 ECM minimum
const DEFAULT_PENALTY_BPS = 2500; // 25% slash on early unstake
const MAX_BPS = 10000; // 100%
const WEEK_SECONDS = 7 * 24 * 3600; // 7 days
const WEEKS_IN_YEAR = 52; // For APR calculations
```

### Provider & Signer
```typescript
import { ethers } from 'ethers';
const provider = new ethers.JsonRpcProvider('https://rpc.testnet.ecmscan.io');
const signer = provider.getSigner();
```

### Contract Instances
```typescript
const poolManager = new ethers.Contract(PoolManagerAddress, PoolManagerABI, signer);
const referralVoucher = new ethers.Contract(ReferralVoucherAddress, ReferralVoucherABI, signer);
const referralModule = new ethers.Contract(ReferralModuleAddress, ReferralModuleABI, signer);
const vestingManager = new ethers.Contract(VestingManagerAddress, VestingManagerABI, signer);
const liquidityManager = new ethers.Contract(LiquidityManagerAddress, LiquidityManagerABI, signer);
```

---

## 2. User Flows

### Purchase & Stake
```typescript
// User selects from allowed stake durations
const selectedDuration = 90 * 24 * 3600; // 90 days (must be in allowedStakeDurations)
await usdt.approve(poolManager.target, usdtAmount);

// Option 1: Buy with max USDT (contract calculates ECM)
await poolManager.buyAndStake(
  poolId, 
  maxUsdtAmount, 
  selectedDuration, 
  voucherInput,  // Use empty/zero values if no referral
  signature
);

// Option 2: Buy exact ECM amount (minimum 500 ECM)
await poolManager.buyExactECMAndStake(
  poolId, 
  exactEcmAmount,  // Must be >= 500 ECM
  maxUsdtAmount,   // Max slippage protection
  selectedDuration, 
  voucherInput, 
  signature
);
```

### Direct Staking (Already Own ECM)
```typescript
// For users who already have ECM tokens
await ecm.approve(poolManager.target, ecmAmount);
await poolManager.stakeECM(poolId, ecmAmount, selectedDuration);
```

### Claim Rewards
```typescript
// Claim without unstaking
await poolManager.claimRewards(poolId);
// If vestRewardsByDefault = true, rewards are vested via VestingManager
// Otherwise, rewards are paid immediately
```

### Unstake
```typescript
// Unstake principal and claim rewards
await poolManager.unstake(poolId);
// If unstaked early: principal is slashed by penaltyBps (default 25%)
// If matured: full principal returned
// Rewards are NEVER slashed
```

### Set Referrer After Purchase
```typescript
// One-time only: set referrer after initial purchase
await poolManager.setMyReferrer(voucherInput, signature);
```

---

## 3. Referral System Integration (EIP-712 Vouchers)

### Off-Chain Voucher Generation
```typescript
// See README.md for full example
const voucher = { ... };
const signature = await issuerSigner.signTypedData(domain, types, voucher);
```

### Frontend Redemption
```typescript
await poolManager.buyAndStake(poolId, maxUsdtAmount, stakeDuration, voucher, signature);
```

---

## 4. Event Subscriptions

### Listen for Key Events
```typescript
// PoolManager Events
poolManager.on('PoolCreated', (poolId, ecm, usdt, pair, strategy) => { ... });
poolManager.on('BoughtAndStaked', (poolId, user, ecmAmount, usdtPaid, stakeDuration, referrer, codeHash) => { ... });
poolManager.on('ECMStaked', (poolId, user, ecmAmount, stakeDuration) => { ... });
poolManager.on('Unstaked', (poolId, user, principalReturned, rewardsPaid) => { ... });
poolManager.on('EarlyUnstaked', (poolId, user, principalReturned, slashed, rewardsPaid) => { ... });
poolManager.on('RewardsClaimed', (poolId, user, amount, vested) => { ... });
poolManager.on('RewardsVested', (poolId, user, amount, vestingId, duration) => { ... });
poolManager.on('LiquidityTransferToManager', (poolId, liquidityManager, ecmAmount, usdtAmount) => { ... });
poolManager.on('LiquidityAddedToUniswap', (poolId, ecmAmount, usdtAmount) => { ... });
poolManager.on('LinearRewardRateSet', (poolId, rewardRatePerSecond) => { ... });
poolManager.on('MonthlyRewardsSet', (poolId, monthlyAmounts) => { ... });
poolManager.on('WeeklyRewardsSet', (poolId, weeklyAmounts) => { ... });

// ReferralModule Events
referralModule.on('DirectCommissionPaid', (referrer, amount, token) => { ... });
referralModule.on('ReferralPayoutClaimed', (epochId, claimer, token, amount) => { ... });
referralModule.on('ReferrerLinked', (user, referrer, codeHash) => { ... });

// VestingManager Events
vestingManager.on('VestingCreated', (vestingId, beneficiary, amount, duration) => { ... });
vestingManager.on('VestedClaimed', (vestingId, beneficiary, amount, remaining) => { ... });
```

---

## 5. Off-Chain Calculations (Referral Commissions, Merkle Trees)

### Multi-Level Commission Calculation
```typescript
// See README.md for full TypeScript algorithm
const commissions = calculateMultiLevelCommissions(...);
const { root, proofs } = buildMerkleTree(commissions);
```

### Merkle Proof Claim
```typescript
await referralModule.claimReferral(epochId, token, amount, proof);
```

---

## 6. Vesting Tracking

### Query Vesting Schedules
```typescript
const vestingIds = await vestingManager.getUserVestingIds(userAddress);
const schedule = await vestingManager.getVestingSchedule(vestingIds[0]);
```

### Claim Vested Tokens
```typescript
await vestingManager.claimVested(vestingId);
```

---

### 7. Error Handling

### Common Errors from PoolManager.sol
- `PoolNotActive()` - Pool is paused/inactive
- `InvalidAddress()` - Zero address provided
- `InvalidStakeDuration()` - Duration not in allowedStakeDurations
- `InsufficientPoolECM()` - Not enough ECM allocated for sale
- `SlippageExceeded()` - Price moved beyond maxUsdtAmount
- `MinPurchaseNotMet()` - Purchase below 500 ECM minimum
- `PoolDoesNotExist()` - Invalid poolId
- `NotStaked()` - User has no active stake
- `InvalidRewards()` - Empty reward array
- `InvalidPenaltyBps()` - Penalty exceeds MAX_BPS (10000)
- `InvalidAmount()` - Zero or invalid amount
- `InvalidStrategy()` - Wrong reward strategy
- `ExceedsAllocatedRewards()` - Reward schedule exceeds allocated
- `InsufficientLiquidity()` - Not enough liquidity in Uniswap pair
- `CannotWithdrawStakedTokens()` - Attempted to withdraw user stakes
- `InvalidDuration()` - Invalid duration configuration
- `NotAuthorizedVestingManager()` - Caller not VestingManager
- `NotAuthorizedLiquidityManager()` - Caller not authorized
- `VestingFailed()` - Vesting creation failed
- `InsufficientECMForLiquidityTransfer()` - Not enough ECM for liquidity
- `InsufficientRewardsForRate()` - Cannot sustain reward rate

### Referral-Related Errors
- Voucher expired or revoked
- Max uses exceeded
- Invalid Merkle proof
- Already claimed commission
- **User already has referrer** (when calling setMyReferrer)
- **Self-referral attempt** (user trying to refer themselves)
- **Referral cycle detected** (circular referral relationships)

### Handling Example
```typescript
try {
  await poolManager.buyAndStake(...);
} catch (err) {
  if (err.message.includes('expired')) {
    // Show voucher expired message
  } else if (err.message.includes('penalty')) {
    // Show early unstake penalty warning
  } else {
    // Generic error
  }
}

// Specific handling for setMyReferrer
try {
  await poolManager.setMyReferrer(voucherInput, signature);
} catch (err) {
  if (err.message.includes('already has referrer')) {
    // User already has a referrer, cannot change
  } else if (err.message.includes('cannot refer yourself')) {
    // Self-referral attempt
  } else if (err.message.includes('cycle detected')) {
    // Circular referral relationship
  }
}
```

---

## 8. Complete End-to-End Example (TypeScript/Ethers v6)

```typescript
// 1. Generate voucher off-chain (optional - for referral)
const { voucher, signature } = await generateVoucher(...);
// If no referral: use empty voucherInput with zero values

// 2. User approves USDT
await usdt.approve(poolManager.target, maxUsdtAmount);

// 3. User buys and stakes (with or without referral)
const selectedDuration = 90 * 24 * 3600; // Must be in allowedStakeDurations
await poolManager.buyAndStake(
  poolId, 
  maxUsdtAmount, 
  selectedDuration, 
  voucher,      // voucherInput struct
  signature     // EIP-712 signature
);

// 4. Listen for BoughtAndStaked event
poolManager.on('BoughtAndStaked', (poolId, user, ecmAmount, usdtPaid, stakeDuration, referrer, codeHash) => {
  console.log('User:', user);
  console.log('Staked:', ecmAmount.toString(), 'ECM');
  console.log('Paid:', usdtPaid.toString(), 'USDT');
  console.log('Duration:', stakeDuration.toString(), 'seconds');
  console.log('Referrer:', referrer); // address(0) if no referral
});

// 5. Check pending rewards
const pending = await poolManager.pendingRewards(poolId, user.address);
console.log('Pending rewards:', pending.toString());

// 6. Claim rewards without unstaking
await poolManager.claimRewards(poolId);

// 7. Listen for RewardsClaimed event
poolManager.on('RewardsClaimed', (poolId, user, amount, vested) => {
  console.log('Rewards claimed:', amount.toString());
  console.log('Vested:', vested); // true if sent to VestingManager
});

// 8. If rewards are vested, listen for RewardsVested event
poolManager.on('RewardsVested', (poolId, user, amount, vestingId, duration) => {
  console.log('Rewards vested:', amount.toString());
  console.log('VestingId:', vestingId.toString());
  console.log('Vesting duration:', duration.toString());
});

// 9. Set referrer after purchase (one-time only)
if (userWantsToAddReferrer && !hasExistingReferrer) {
  // Delegated via PoolManager (recommended)
  await poolManager.setMyReferrer(voucherInput, voucherSignature);
  
  // Listen for ReferrerLinked event from ReferralModule
  referralModule.on('ReferrerLinked', (user, referrer, codeHash) => {
    console.log('Referrer linked:', referrer, 'for user:', user);
  });
}

// 10. Check unstake penalty before unstaking
const penalty = await poolManager.calculateUnstakePenalty(poolId, user.address);
console.log('Will be penalized:', penalty.willBePenalized);
console.log('Penalty amount:', penalty.penaltyAmount.toString());
console.log('Amount received:', penalty.amountReceived.toString());
console.log('Time until maturity:', penalty.timeUntilMaturity.toString());

// 11. Unstake (with or without penalty)
await poolManager.unstake(poolId);

// 12. Listen for Unstaked or EarlyUnstaked event
poolManager.on('EarlyUnstaked', (poolId, user, principalReturned, slashed, rewardsPaid) => {
  console.log('Principal returned:', principalReturned.toString());
  console.log('Slashed:', slashed.toString()); // 25% of staked by default
  console.log('Rewards paid:', rewardsPaid.toString());
});

poolManager.on('Unstaked', (poolId, user, principalReturned, rewardsPaid) => {
  console.log('Principal returned (matured):', principalReturned.toString());
  console.log('Rewards paid:', rewardsPaid.toString());
});

// 13. If rewards were vested, claim vested tokens
const vestingIds = await vestingManager.getUserVestingIds(user.address);
if (vestingIds.length > 0) {
  const vestingSchedule = await vestingManager.getVestingSchedule(vestingIds[0]);
  const claimable = await vestingManager.calculateClaimable(vestingIds[0]);
  console.log('Claimable vested:', claimable.toString());
  
  await vestingManager.claimVested(vestingIds[0]);
}

// 14. Claim multi-level referral commission (with Merkle proof)
await referralModule.claimReferral(epochId, token, amount, proof);
```

---

## Additional Resources
- See ARCHITECTURE_DIAGRAMS.md for full system diagrams and flows
- See README.md for contract details, data structures, and off-chain algorithms
- See test/pool-manager.ts for comprehensive integration tests

---

**For questions or support, contact the ECM Pool development team.**