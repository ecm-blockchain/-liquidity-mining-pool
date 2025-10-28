# Pool Creation & Configuration Guide

## Pre-Deployment Guide (Pool Creation Prerequisites)

### 1. Prerequisites
- **Admin Wallet**: Secure wallet with sufficient ECM and USDT for allocations
- **Contract Deployment**: PoolManager, LiquidityManager, VestingManager, ReferralModule, ReferralVoucher deployed and verified
- **Token Approvals**: Admin must approve PoolManager to spend ECM and USDT for sale, rewards, and liquidity
- **Uniswap V2 Pair**: ECM/USDT pair deployed and address known
- **Penalty Receiver**: Treasury or burn address for slashed tokens
- **Allowed Stake Durations**: Decide durations (e.g., [30 days, 90 days, 180 days])
- **Vesting Duration**: Set vesting period for rewards (if using vesting)
- **Reward Strategy**: Choose LINEAR or MONTHLY, and prepare monthly schedule if needed
- **Liquidity Reserve**: Decide ECM/USDT amounts for initial liquidity
- **Referral System**: Configure ReferralModule and ReferralVoucher (if using referrals)

### 2. Pool Creation Steps
1. **Approve ECM for Sale**:
   - `ecm.approve(poolManager.address, saleAmount)`
2. **Approve ECM for Rewards**:
   - `ecm.approve(poolManager.address, rewardAmount)`
3. **Approve ECM/USDT for Liquidity** (if using LiquidityManager):
   - `ecm.approve(poolManager.address, liquidityAmount)`
   - `usdt.approve(poolManager.address, liquidityUsdtAmount)`
4. **Create Pool**:
   - Call `poolManager.createPool(ecm, usdt, uniswapPair, penaltyReceiver, strategy, allowedStakeDurations, vestingDuration, vestRewardsByDefault)`
   - Save returned `poolId`
5. **Allocate ECM for Sale**:
   - `poolManager.allocateForSale(poolId, saleAmount)`
6. **Allocate ECM for Rewards**:
   - `poolManager.allocateForRewards(poolId, rewardAmount)`
7. **Set Liquidity Reserve** (optional):
   - `poolManager.setLiquidityReserve(poolId, liquidityAmount)`
8. **Configure Reward Strategy**:
   - For LINEAR: `poolManager.setLinearRewardRate(poolId, rewardRatePerSecond)`
   - For MONTHLY: `poolManager.setMonthlyRewards(poolId, [month1, month2, ...])`
9. **Configure Penalty**:
   - `poolManager.setPenaltyConfig(poolId, penaltyBps, penaltyReceiver)`
10. **Configure Vesting** (optional):
    - `poolManager.setVestingConfig(poolId, vestingDuration, vestByDefault)`
11. **Activate Pool**:
    - `poolManager.setPoolActive(poolId, true)`

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
  - For LINEAR: `poolManager.setLinearRewardRate(poolId, newRate)`
  - For MONTHLY: `poolManager.setMonthlyRewards(poolId, [newSchedule])`
- **Add More ECM for Sale/Rewards**:
  - `poolManager.allocateForSale(poolId, additionalAmount)`
  - `poolManager.allocateForRewards(poolId, additionalAmount)`
- **Update Liquidity Reserve**:
  - `poolManager.setLiquidityReserve(poolId, newLiquidityAmount)`
- **Pause/Unpause Pool**:
  - `poolManager.setPoolActive(poolId, false)` / `true`
- **Emergency Token Recovery**:
  - `poolManager.emergencyRecoverTokens(token, amount)` (never touches user stakes)

### 2. Liquidity Management
- **Transfer to LiquidityManager**:
  - `poolManager.transferToLiquidityManager(ecmAmount, usdtAmount, liquidityManager)`
- **Add Liquidity on Uniswap**:
  - `liquidityManager.addLiquidity(ecmAmount, usdtAmount, minEcm, minUsdt, to, deadline)`

### 3. VestingManager Operations
- **Set VestingManager Contract**:
  - `poolManager.setVestingManager(vestingManagerAddress)`
- **Create Vesting Schedules**:
  - Handled automatically on reward claim if vesting enabled
- **Claim Vested Tokens**:
  - `vestingManager.claimVested(vestingId)`

### 4. Referral System Operations
- **Set ReferralModule/ReferralVoucher**:
  - Configure addresses in frontend/off-chain logic
- **Issue Vouchers**:
  - Off-chain EIP-712 signing (see README)
- **Claim Referral Commissions**:
  - `referralModule.claimReferral(epochId, token, amount, proof)`

---

## Best Practices & Tips
- Always update pool rewards before changing configuration (call `_updatePoolRewards(poolId)` if needed)
- Use SafeERC20 for all token transfers
- Never sweep user-staked tokens; only admin or liquidity reserves
- Document all pool parameters and configuration changes for auditability
- Monitor events for pool status, reward accrual, and user actions
- Use test suite to validate all admin and user flows before launch

---

**For full API details, see README.md and contract source.**
# Frontend Integration Guide: StakingPool (ethers v6 + TS/JS)
stakingPool.on("Claim", (user, amount, poolId) => {

# ECM Liquidity Mining Pool - Integration Guide

This guide provides a complete reference for integrating the ECM Liquidity Mining Pool system into your frontend, backend, or off-chain services. It covers contract connections, user flows, referral system integration, event subscriptions, off-chain calculations, vesting tracking, error handling, and end-to-end code examples.

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

---

## 1. Setup & Connection

### Contract Addresses
- PoolManager: `0x...`
- ReferralVoucher: `0x...`
- ReferralModule: `0x...`
- VestingManager: `0x...`
- LiquidityManager: `0x...`

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
await usdt.approve(poolManager.target, usdtAmount);
await poolManager.buyAndStake(poolId, maxUsdtAmount, stakeDuration, voucherInput, signature);
```

### Buy Exact ECM & Stake
```typescript
await poolManager.buyExactECMAndStake(poolId, exactEcmAmount, maxUsdtAmount, stakeDuration, voucherInput, signature);
```

### Claim Rewards
```typescript
await poolManager.claimRewards(poolId);
```

### Unstake
```typescript
await poolManager.unstake(poolId);
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
poolManager.on('BoughtAndStaked', (user, poolId, ecm, usdt, duration) => { ... });
poolManager.on('Unstaked', (user, poolId, amount) => { ... });
poolManager.on('EarlyUnstaked', (user, poolId, amount, slashed) => { ... });
poolManager.on('RewardsClaimed', (user, poolId, amount) => { ... });
poolManager.on('RewardsVested', (user, poolId, amount, vestingId) => { ... });
referralModule.on('DirectCommissionPaid', (referrer, amount, token) => { ... });
referralModule.on('ReferralPayoutClaimed', (epochId, claimer, token, amount) => { ... });
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

## 7. Error Handling

### Common Errors
- Insufficient USDT/ECM balance
- Voucher expired or revoked
- Max uses exceeded
- Not authorized (onlyOwner, onlyPoolManager)
- Invalid Merkle proof
- Already claimed commission
- Early unstake penalty
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
// 1. Generate voucher off-chain
const { voucher, signature } = await generateVoucher(...);

// 2. User approves USDT
await usdt.approve(poolManager.target, usdtAmount);

// 3. User buys and stakes with referral
await poolManager.buyAndStake(poolId, maxUsdtAmount, stakeDuration, voucher, signature);

// 4. Listen for BoughtAndStaked event
poolManager.on('BoughtAndStaked', (user, poolId, ecm, usdt, duration) => {
  console.log('Staked:', ecm.toString());
});

// 5. Claim rewards
await poolManager.claimRewards(poolId);

// 6. Listen for RewardsClaimed or RewardsVested
poolManager.on('RewardsClaimed', (user, poolId, amount) => {
  console.log('Rewards claimed:', amount.toString());
});
poolManager.on('RewardsVested', (user, poolId, amount, vestingId) => {
  console.log('Rewards vested:', amount.toString(), 'vestingId:', vestingId.toString());
});

// 7. Set referrer after purchase (if user didn't provide during step 3)
if (userWantsToAddReferrer && !hasExistingReferrer) {
  // Option A: Direct call to ReferralModule
  await referralModule.setMyReferrer(voucherInput, voucherSignature);
  
  // Option B: Delegated via PoolManager (recommended)
  await poolManager.setMyReferrer(voucherInput, voucherSignature);
  
  // Listen for ReferrerLinked event
  referralModule.on('ReferrerLinked', (user, referrer, codeHash) => {
    console.log('Referrer linked:', referrer, 'for user:', user);
  });
}

// 8. Claim vested tokens
const vestingIds = await vestingManager.getUserVestingIds(user.address);
await vestingManager.claimVested(vestingIds[0]);

// 9. Claim multi-level referral commission (with proof)
await referralModule.claimReferral(epochId, token, amount, proof);
```

---

## Additional Resources
- See ARCHITECTURE_DIAGRAMS.md for full system diagrams and flows
- See README.md for contract details, data structures, and off-chain algorithms
- See test/pool-manager.ts for comprehensive integration tests

---

**For questions or support, contact the ECM Pool development team.**