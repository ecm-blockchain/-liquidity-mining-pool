# Contract Functions Reference

## Table of Contents

1. [PoolManager Functions](#poolmanager-functions)
2. [ReferralVoucher Functions](#referralvoucher-functions)
3. [ReferralModule Functions](#referralmodule-functions)
4. [VestingManager Functions](#vestingmanager-functions)
5. [LiquidityManager Functions](#liquiditymanager-functions)
6. [Function Categories Legend](#function-categories-legend)

---

## PoolManager Functions

### Admin Functions (onlyOwner)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **Pool Creation & Configuration** |
| `createPool` | `PoolCreateParams` | Creates new pool with ECM/USDT pair | ~500K |
| `allocateForSale` | `poolId`, `amount` | Allocates ECM tokens for sale | ~100K |
| `allocateForRewards` | `poolId`, `amount` | Allocates ECM tokens for rewards | ~100K |
| `setPoolActive` | `poolId`, `active` | Activates/deactivates pool | ~50K |
| **Reward Strategy Configuration** |
| `setLinearRewardRate` | `poolId` | Auto-calculates LINEAR reward rate | ~80K |
| `setMonthlyRewards` | `poolId`, `monthlyAmounts[]` | Configures MONTHLY reward schedule | ~120K |
| `setWeeklyRewards` | `poolId`, `weeklyAmounts[]` | Configures WEEKLY reward schedule | ~120K |
| **Pool Settings** |
| `setAllowedStakeDurations` | `poolId`, `durations[]` | Updates allowed stake durations | ~80K |
| `setPenaltyConfig` | `poolId`, `penaltyBps`, `penaltyReceiver` | Updates early unstake penalty config | ~60K |
| `setVestingConfig` | `poolId`, `vestingDuration`, `vestByDefault` | Updates vesting configuration | ~60K |
| **System Configuration** |
| `setVestingManager` | `address` | Sets VestingManager contract address | ~50K |
| `setReferralVoucher` | `address` | Sets ReferralVoucher contract address | ~50K |
| `setReferralModule` | `address` | Sets ReferralModule contract address | ~50K |
| **Liquidity Management** |
| `addAuthorizedLiquidityManager` | `manager` | Authorizes LiquidityManager contract | ~50K |
| `removeAuthorizedLiquidityManager` | `manager` | Removes LiquidityManager authorization | ~50K |
| `transferToLiquidityManager` | `poolId`, `manager`, `ecmAmount`, `usdtAmount` | Transfers tokens to LiquidityManager | ~150K |
| **Emergency Controls** |
| `pause` | - | Pauses all user operations | ~30K |
| `unpause` | - | Resumes operations | ~30K |
| `emergencyRecoverTokens` | `token`, `amount`, `to` | Recovers mistakenly sent tokens | ~80K |
| **Ownership** |
| `transferOwnership` | `newOwner` | Transfers contract ownership | ~50K |
| `renounceOwnership` | - | Renounces ownership (irreversible) | ~30K |

### User Functions (Public/External)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **Buy & Stake** |
| `buyAndStake` | `poolId`, `maxUsdtAmount`, `selectedStakeDuration`, `voucherInput`, `voucherSignature` | Buys ECM with USDT and auto-stakes | ~350K |
| `buyExactECMAndStake` | `poolId`, `exactEcmAmount`, `maxUsdtAmount`, `selectedStakeDuration`, `voucherInput`, `voucherSignature` | Buys exact ECM amount and stakes | ~350K |
| `stakeECM` | `poolId`, `ecmAmount`, `selectedStakeDuration` | Stakes already-owned ECM tokens | ~250K |
| **Unstake & Claim** |
| `unstake` | `poolId` | Unstakes tokens and claims rewards | ~300K |
| `claimRewards` | `poolId` | Claims rewards without unstaking | ~200K |
| **Referral** |
| `setMyReferrer` | `voucherInput`, `voucherSignature` | Sets referrer after purchase (one-time) | ~150K |

### View Functions (Read-Only)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| **Pool Information** |
| `poolCount` | - | `uint256` | Total number of pools created |
| `getPoolInfo` | `poolId` | `Pool` | Complete pool information struct |
| `pools` | `poolId` | `Pool` | Direct pool storage access |
| **User Information** |
| `getUserInfo` | `poolId`, `user` | `UserInfo` | User's stake and reward info |
| `userInfo` | `poolId`, `user` | `UserInfo` | Direct userInfo storage access |
| `pendingRewards` | `poolId`, `user` | `uint256` | User's pending unclaimed rewards |
| **Pricing & Estimation** |
| `getPriceSpot` | `poolId` | `usdtPerEcm`, `reserveECM`, `reserveUSDT` | Current spot price from Uniswap |
| `getRequiredUSDTForExactECM` | `poolId`, `exactEcm` | `uint256` | USDT needed for exact ECM amount |
| `estimateECMForUSDT` | `poolId`, `usdtAmount` | `uint256` | ECM estimate for USDT amount |
| **Balance & Accounting** |
| `getPoolBalanceStatus` | `poolId` | 10 values | Comprehensive pool balance breakdown |
| **Analytics & Metrics** |
| `calculateAPR` | `poolId`, `periodsToProject` | `uint256` | Annual Percentage Rate (scaled by 1e18) |
| `calculateExpectedRewards` | `poolId`, `user`, `durationSeconds` | `uint256` | Expected rewards over time period |
| `calculateROI` | `poolId`, `user`, `durationSeconds`, `ecmPriceInUsdt` | `uint256` | Return on Investment percentage |
| `calculateTVL` | `poolId`, `ecmPriceInUsdt` | `uint256` | Total Value Locked in USDT |
| `calculateUtilizationRate` | `poolId` | `uint256` | Pool utilization percentage |
| `calculateRewardDepletionTime` | `poolId` | 3 values | Estimated reward depletion forecast |
| `getPoolAnalytics` | `poolId`, `ecmPriceInUsdt` | 8 values | Comprehensive pool analytics |
| `getUserAnalytics` | `poolId`, `user` | 8 values | Comprehensive user analytics |
| `calculateUnstakePenalty` | `poolId`, `user` | 4 values | Early unstake penalty calculation |
| **System Configuration** |
| `vestingManager` | - | `address` | VestingManager contract address |
| `referralVoucher` | - | `address` | ReferralVoucher contract address |
| `referralModule` | - | `address` | ReferralModule contract address |
| `UNISWAP_ROUTER` | - | `address` | Uniswap V2 Router address (immutable) |
| `authorizedLiquidityManagers` | `manager` | `bool` | Check if manager is authorized |

### Authorized External Functions

| Function | Caller | Parameters | Description |
|----------|--------|-----------|-------------|
| `recordLiquidityAdded` | Authorized LiquidityManager | `poolId`, `ecmAmount`, `usdtAmount` | Records liquidity added to Uniswap |
| `refillPoolManager` | Authorized LiquidityManager | `poolId`, `ecmAmount` | Returns unused ECM to pool |

---

## ReferralVoucher Functions

### Admin Functions (onlyOwner)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **Authorization** |
| `setPoolManager` | `address` | Sets PoolManager contract address | ~50K |
| `setReferralModule` | `address` | Sets ReferralModule contract address (dual auth) | ~50K |
| `addIssuer` | `issuer` | Adds authorized voucher issuer | ~50K |
| `removeIssuer` | `issuer` | Removes voucher issuer authorization | ~50K |
| **Voucher Management** |
| `revokeVoucher` | `vid` | Revokes specific voucher by ID | ~50K |
| **Ownership** |
| `transferOwnership` | `newOwner` | Transfers contract ownership | ~50K |
| `renounceOwnership` | - | Renounces ownership | ~30K |

### Authorized External Functions

| Function | Caller | Parameters | Description |
|----------|--------|-----------|-------------|
| `useVoucher` | PoolManager OR ReferralModule | `vid`, `buyer`, `purchaseAmount` | Uses voucher and records usage |

### View Functions (Read-Only)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `verifyVoucher` | `voucherInput`, `signature` | `bool`, `string` | Verifies voucher signature and validity |
| `getVoucherInfo` | `vid` | `VoucherInfo` | Gets voucher details |
| `isVoucherValid` | `vid` | `bool` | Checks if voucher is valid |
| `isIssuer` | `address` | `bool` | Checks if address is authorized issuer |
| `poolManager` | - | `address` | PoolManager address |
| `referralModule` | - | `address` | ReferralModule address |
| `usageCount` | `vid` | `uint256` | Times voucher has been used |
| `hasUsedVoucher` | `buyer`, `vid` | `bool` | Check if buyer used voucher |

---

## ReferralModule Functions

### Admin Functions (onlyOwner)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **System Configuration** |
| `setPoolManager` | `address` | Sets PoolManager contract address | ~50K |
| `setReferralVoucher` | `address` | Sets ReferralVoucher contract address | ~50K |
| **Commission Configuration** |
| `setPoolLevelConfig` | `poolId`, `levelBps[]` | Sets multi-level commission rates per pool | ~100K |
| `setDefaultLevelConfig` | `levelBps[]` | Sets default multi-level commission rates | ~100K |
| **Fund Management** |
| `fundContract` | `token`, `amount` | Funds contract for direct commissions | ~80K |
| `withdrawFunds` | `token`, `amount`, `to` | Withdraws contract funds | ~80K |
| **Merkle Root Submission** |
| `submitReferralPayoutRoot` | `epochId`, `token`, `totalAmount`, `root`, `expiry` | Submits Merkle root for multi-level payouts | ~150K |
| `withdrawUnclaimed` | `epochId`, `to` | Withdraws unclaimed funds after expiry | ~80K |
| **Ownership** |
| `transferOwnership` | `newOwner` | Transfers contract ownership | ~50K |
| `renounceOwnership` | - | Renounces ownership | ~30K |

### User Functions (Public/External)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **Referral Management** |
| `recordPurchase` | `poolId`, `buyer`, `purchaseAmount`, `referrer`, `codeHash` | Records purchase with referral | ~200K |
| `setMyReferrer` | `poolId`, `referrerCode`, `voucherInput`, `voucherSignature` | Sets referrer after purchase (one-time) | ~150K |
| `setReferrerFor` | `poolId`, `buyer`, `referrerCode`, `voucherInput`, `voucherSignature` | Sets referrer for another user (with permission) | ~150K |
| **Commission Claims** |
| `claimDirectCommission` | `poolId` | Claims accumulated direct commissions | ~150K |
| `claimReferralPayout` | `epochId`, `token`, `amount`, `proof` | Claims multi-level commission with Merkle proof | ~200K |

### View Functions (Read-Only)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| **Referral Chain** |
| `getReferralChain` | `user`, `maxDepth` | `address[]` | Gets user's upline referral chain |
| `getReferrer` | `user` | `address` | Gets user's direct referrer |
| `hasReferrer` | `user` | `bool` | Checks if user has referrer set |
| `canSetReferrer` | `user` | `bool` | Checks if user can still set referrer |
| **Commission Info** |
| `getPendingDirectCommission` | `poolId`, `user` | `uint256` | User's pending direct commission |
| `getPoolLevelConfig` | `poolId` | `uint16[]` | Multi-level commission rates for pool |
| `getPayoutRootInfo` | `epochId` | `PayoutRootInfo` | Merkle root information for epoch |
| `hasClaimed` | `epochId`, `beneficiary` | `bool` | Check if beneficiary claimed epoch payout |
| **Statistics** |
| `totalDirectPaid` | - | `uint256` | Total direct commissions paid |
| `totalMultiLevelPaid` | - | `uint256` | Total multi-level commissions paid |
| `totalPurchases` | - | `uint256` | Total purchases recorded |
| **Configuration** |
| `poolManager` | - | `address` | PoolManager contract address |
| `referralVoucher` | - | `address` | ReferralVoucher contract address |

---

## VestingManager Functions

### Admin Functions (onlyOwner)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **Authorization** |
| `addAuthorizedCreator` | `creator` | Authorizes address to create vestings | ~50K |
| `removeAuthorizedCreator` | `creator` | Removes creator authorization | ~50K |
| **Vesting Management** |
| `revokeVesting` | `vestingId` | Revokes vesting schedule (emergency) | ~80K |
| **Ownership** |
| `transferOwnership` | `newOwner` | Transfers contract ownership | ~50K |
| `renounceOwnership` | - | Renounces ownership | ~30K |

### Authorized External Functions

| Function | Caller | Parameters | Description |
|----------|--------|-----------|-------------|
| `createVesting` | Authorized Creator (PoolManager) | `beneficiary`, `amount`, `start`, `duration`, `token`, `poolId` | Creates linear vesting schedule |

### User Functions (Public/External)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| `claimVested` | `vestingId` | Claims vested tokens from schedule | ~150K |

### View Functions (Read-Only)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `getVestingInfo` | `vestingId` | `VestingSchedule` | Gets vesting schedule details |
| `getUserVestingIds` | `beneficiary` | `uint256[]` | Gets all vesting IDs for user |
| `calculateVested` | `vestingId` | `uint256` | Calculates currently vested amount |
| `calculateClaimable` | `vestingId` | `uint256` | Calculates claimable (vested - claimed) |
| `nextVestingId` | - | `uint256` | Next vesting ID to be assigned |
| `authorizedCreators` | `address` | `bool` | Checks if address can create vestings |

---

## LiquidityManager Functions

### Admin Functions (onlyOwner)

| Function | Parameters | Description | Gas Est. |
|----------|-----------|-------------|----------|
| **System Configuration** |
| `setPoolManager` | `address` | Sets PoolManager contract address | ~50K |
| `setTreasury` | `address` | Sets treasury address for LP tokens | ~50K |
| **Liquidity Operations** |
| `addLiquidityWithTracking` | `params`, `poolId`, `tokenToTrack` | Adds liquidity and reports to PoolManager | ~400K |
| `addLiquidity` | `params` | Adds liquidity without tracking | ~350K |
| `removeLiquidity` | `params` | Removes liquidity from Uniswap | ~300K |
| **Token Management** |
| `approveTokenForRouter` | `token`, `amount` | Approves token for Uniswap Router | ~50K |
| `withdrawToken` | `token`, `amount`, `to` | Withdraws tokens from contract | ~80K |
| `refillPoolManager` | `poolId`, `ecmAmount` | Returns unused ECM to PoolManager | ~150K |
| **Ownership** |
| `transferOwnership` | `newOwner` | Transfers contract ownership | ~50K |
| `renounceOwnership` | - | Renounces ownership | ~30K |

### View Functions (Read-Only)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `poolManager` | - | `address` | PoolManager contract address |
| `router` | - | `address` | Uniswap V2 Router address |
| `treasury` | - | `address` | Treasury address |

---

## Function Categories Legend

### Access Control Categories

| Category | Description | Who Can Call |
|----------|-------------|--------------|
| **Admin** | Owner-only functions | Contract owner (should be multisig) |
| **Authorized** | Restricted to authorized contracts | Whitelisted contract addresses |
| **User** | Public functions with restrictions | Any user meeting requirements |
| **View** | Read-only functions | Anyone (no gas cost when called off-chain) |

### Gas Estimation Notes

- Gas estimates are approximate and vary based on:
  - Network congestion
  - Storage state (cold vs warm)
  - Transaction complexity
  - Array lengths
- Add 20-30% buffer for production
- Use `eth_estimateGas` for accurate estimates

### Function Naming Conventions

| Prefix | Type | Example |
|--------|------|---------|
| `set*` | Configuration setter | `setPoolActive` |
| `get*` | Data getter | `getPoolInfo` |
| `calculate*` | Off-chain calculation | `calculateAPR` |
| `add*` | Add to collection | `addAuthorizedLiquidityManager` |
| `remove*` | Remove from collection | `removeIssuer` |
| `claim*` | Claim rewards/funds | `claimRewards` |
| `withdraw*` | Withdraw funds | `withdrawFunds` |
| `record*` | Record data | `recordLiquidityAdded` |

---

## Quick Reference: Most Used Functions

### For Admins

**Daily Operations:**
```solidity
poolManager.getPoolInfo(poolId)           // Check pool status
poolManager.calculateRewardDepletionTime(poolId)  // Monitor rewards
poolManager.getPoolBalanceStatus(poolId)  // Verify accounting
```

**Weekly Operations:**
```solidity
poolManager.allocateForRewards(poolId, amount)  // Add rewards
poolManager.setLinearRewardRate(poolId)         // Update rate
referralModule.submitReferralPayoutRoot(...)    // Submit commissions
```

**Monthly Operations:**
```solidity
poolManager.createPool(params)                  // New pool
liquidityManager.addLiquidityWithTracking(...)  // Add liquidity
vestingManager.addAuthorizedCreator(creator)    // Update auth
```

### For Users

**Buy & Stake:**
```solidity
poolManager.buyAndStake(poolId, maxUsdt, duration, voucher, sig)
poolManager.buyExactECMAndStake(poolId, exactEcm, maxUsdt, duration, voucher, sig)
```

**Manage Stakes:**
```solidity
poolManager.pendingRewards(poolId, user)  // Check rewards
poolManager.claimRewards(poolId)          // Claim without unstaking
poolManager.unstake(poolId)               // Unstake + claim
```

**Referrals:**
```solidity
referralModule.setMyReferrer(poolId, code, voucher, sig)
referralModule.claimDirectCommission(poolId)
referralModule.claimReferralPayout(epoch, token, amount, proof)
```

**Vesting:**
```solidity
vestingManager.getUserVestingIds(user)     // Check schedules
vestingManager.calculateClaimable(vestingId)  // Check claimable
vestingManager.claimVested(vestingId)      // Claim vested
```

---

## Function Call Flow Diagrams

### Buy & Stake Flow
```
User → buyAndStake()
  ├─→ validateParams()
  ├─→ _updatePoolRewards()
  ├─→ _calculatePurchaseAmounts()
  ├─→ USDT.transferFrom() [User → PoolManager]
  ├─→ _handleReferralVoucher()
  │   └─→ ReferralVoucher.useVoucher()
  │       └─→ ReferralModule.recordPurchase()
  ├─→ _executeAutoStake()
  └─→ emit BoughtAndStaked()
```

### Unstake Flow
```
User → unstake()
  ├─→ _updatePoolRewards()
  ├─→ Calculate pending rewards
  ├─→ Check maturity (early vs mature)
  ├─→ If early: calculate penalty
  │   ├─→ ECM.transfer() [penalty to penaltyReceiver]
  │   └─→ ECM.transfer() [remaining to user]
  ├─→ If mature: ECM.transfer() [full to user]
  ├─→ _claimOrVestRewards()
  │   ├─→ If vesting: VestingManager.createVesting()
  │   └─→ If immediate: ECM.transfer() [rewards to user]
  └─→ emit Unstaked() / EarlyUnstaked()
```

### Multi-Level Commission Flow
```
Backend → submitReferralPayoutRoot()
  ├─→ Build Merkle tree from commission data
  ├─→ ECM.transferFrom() [Admin → ReferralModule]
  ├─→ Store root + metadata
  └─→ emit ReferralPayoutRootSubmitted()

User → claimReferralPayout()
  ├─→ Verify Merkle proof
  ├─→ Check not expired
  ├─→ Check not already claimed
  ├─→ ECM.transfer() [ReferralModule → User]
  └─→ emit ReferralPayoutClaimed()
```

---

## Integration Checklist

### Frontend Integration

**Required View Functions:**
- [ ] `poolManager.getPoolInfo()` - Pool details
- [ ] `poolManager.getUserInfo()` - User stake info
- [ ] `poolManager.pendingRewards()` - Pending rewards
- [ ] `poolManager.getPriceSpot()` - Current ECM price
- [ ] `poolManager.calculateAPR()` - Display APR
- [ ] `vestingManager.getUserVestingIds()` - Vesting schedules
- [ ] `referralModule.getPendingDirectCommission()` - Referral earnings

**Required Write Functions:**
- [ ] `poolManager.buyAndStake()` - Main purchase flow
- [ ] `poolManager.claimRewards()` - Claim button
- [ ] `poolManager.unstake()` - Unstake button
- [ ] `referralModule.claimDirectCommission()` - Claim referrals
- [ ] `vestingManager.claimVested()` - Claim vested tokens

### Backend Integration

**Required Event Listeners:**
- [ ] `PoolCreated` - Track new pools
- [ ] `BoughtAndStaked` - Track purchases
- [ ] `Unstaked` / `EarlyUnstaked` - Track unstakes
- [ ] `RewardsClaimed` - Track reward claims
- [ ] `PurchaseRecorded` (ReferralModule) - Track referrals
- [ ] `RewardClaimRecorded` (ReferralModule) - Calculate commissions

**Required Admin Functions:**
- [ ] `referralModule.submitReferralPayoutRoot()` - Submit commissions
- [ ] `poolManager.allocateForRewards()` - Fund pools
- [ ] `liquidityManager.addLiquidityWithTracking()` - Manage liquidity

---

## Appendix: Struct Definitions

### PoolCreateParams
```solidity
struct PoolCreateParams {
    address ecm;                    // ECM token address
    address usdt;                   // USDT token address
    address pair;                   // Uniswap V2 pair address
    address penaltyReceiver;        // Where penalties go
    RewardStrategy rewardStrategy;  // 0=LINEAR, 1=MONTHLY, 2=WEEKLY
    uint256[] allowedStakeDurations; // Allowed durations
    uint256 maxDuration;            // Max duration for rate calc
    uint256 vestingDuration;        // Vesting period
    bool vestRewardsByDefault;      // Auto-vest rewards
    uint16 penaltyBps;              // Penalty in basis points
}
```

### VoucherInput
```solidity
struct VoucherInput {
    bytes32 vid;            // Voucher ID
    bytes32 codeHash;       // Referral code hash
    address owner;          // Voucher owner (referrer)
    uint16 directBps;       // Direct commission %
    bool transferOnUse;     // Immediate transfer flag
    uint64 expiry;          // Expiry timestamp
    uint32 maxUses;         // Max uses (0 = unlimited)
    uint256 nonce;          // Unique nonce
}
```

---


**Related Documentation:**
- [ADMIN_GUIDE.md](./ADMIN_GUIDE.md) - Step-by-step admin operations
- [USER_GUIDE.md](./USER_GUIDE.md) - End-user instructions
- [integration-guide.md](../integration-guide.md) - Frontend/backend integration
- [LINEAR_REWARDS_FIX.md](./LINEAR_REWARDS_FIX.md) - Recent fixes documentation

---