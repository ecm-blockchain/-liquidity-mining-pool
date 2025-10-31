
# ECM Liquidity Mining Pool

## Overview

This repository contains a comprehensive **five-contract architecture** for ECM token sale, staking, reward distribution, referral system, and liquidity management:

- **PoolManager** - Core contract for token sales (USDT→ECM), auto-staking, reward distribution, and referral integration
- **ReferralVoucher** - EIP-712 signature verification for off-chain referral codes
- **ReferralModule** - Two-tier commission system (Direct + Multi-level Merkle distribution)
- **VestingManager** - Linear vesting schedules for reward claims
- **LiquidityManager** - Dedicated Uniswap V2 liquidity operations handler

This system enables users to purchase ECM tokens with USDT using referral codes, automatically stake them, earn rewards (LINEAR/MONTHLY/WEEKLY strategies), participate in multi-level referral commissions, and optionally vest rewards over time. The architecture provides enterprise-grade features with cryptographic security (EIP-712), gas-efficient Merkle distribution, and mathematical precision.

---

## Architecture Overview

### Five-Contract Design

#### 1. PoolManager (Central Hub - 2221 lines)

**PoolManager** is the core contract orchestrating ECM token sales, auto-staking, reward distribution, referral integration, liquidity management, and comprehensive analytics. It supports multiple independent pools with distinct reward strategies.

**Key Features:**
- **Token Sale & Auto-Staking**
  - USDT→ECM purchases at Uniswap V2 spot price from reserves
  - 500 ECM minimum purchase, all amounts must be multiples of 500
  - Single-call UX: `buyAndStake()` combines purchase and staking atomically
  - Slippage protection via `maxUsdtAmount` parameter
  - Exact ECM purchase via `buyExactECMAndStake()`
  - All purchased ECM is automatically staked (no idle balances)

- **Three Reward Strategies**
  - **LINEAR**: Constant reward rate per second (e.g., 1 ECM/sec)
  - **MONTHLY**: Variable rates per month with automatic month progression
  - **WEEKLY**: Variable rates per week with automatic week progression
  - Uses canonical `accRewardPerShare` pattern (scaled by 1e18) for precision

- **Referral System Integration**
  - EIP-712 voucher verification via ReferralVoucher contract
  - Direct commission processing (immediate or accrued) via ReferralModule
  - Multi-level commission event recording for off-chain Merkle distribution
  - Immutable referrer-buyer relationships with anti-gaming rules
  - **Post-purchase referrer setting**: Users can add referral codes after initial purchase via `setMyReferrer()`
  - **Dual access patterns**: Direct call to ReferralModule OR delegated via PoolManager
  - **One-time assignment**: Referrer relationships cannot be changed once set

- **Early Unstaking with Penalties**
  - Configurable principal slashing (default 25% = 2500 bps)
  - Only principal is slashed; rewards remain intact
  - Penalty receiver address (treasury/burn)
  - Maturity check based on selected `stakeDuration` (users choose from allowed durations)

- **Optional Reward Vesting**
  - Linear vesting via VestingManager integration
  - Automatic vesting schedule creation on reward claims
  - Configurable vesting duration per pool
  - Pool-level or user-choice vesting modes

- **Liquidity Management**
  - Explicit ECM/USDT transfers to authorized LiquidityManager contracts
  - Callback tracking for liquidity added to Uniswap V2
  - Two-level accounting: moved to LiquidityManager vs actually added to Uniswap
  - Never touches user-staked tokens (strict segregation)

- **Comprehensive Analytics**
  - 15+ view functions for real-time calculations
  - APR/ROI/TVL calculations with price oracle integration
  - Historical tracking: stakes, unstakes, penalties, rewards
  - Pool-level and user-level analytics

#### 2. ReferralVoucher (EIP-712 Verification - 247 lines)
Off-chain voucher verification system:
- **EIP-712 Signatures**: Cryptographically secure voucher validation
- **Usage Tracking**: Single-use, multi-use, or unlimited vouchers
- **Expiry Enforcement**: Timestamp-based voucher expiration
- **Issuer Management**: Whitelist of authorized voucher signers
- **Revocation Support**: Admin can cancel specific vouchers

#### 3. ReferralModule (Two-Tier Commissions - 505 lines)
Multi-level referral commission system:
- **Direct Commissions**: Immediate or accrued payments on purchases (Tier 1)
- **Multi-Level Commissions**: Merkle-based distribution on reward claims (Tier 2)
- **10-Level Support**: Up to 10 referral chain levels
- **Anti-Gaming Rules**: No self-referral, no cyclic chains, immutable relationships
- **Gas Efficiency**: Off-chain Merkle tree computation, on-chain proof verification

#### 4. VestingManager (Linear Vesting - 526 lines)
Linear vesting system:
- **Pro-Rata Release**: Tokens unlock linearly over time
- **Multiple Schedules**: Users can have multiple independent vesting periods
- **Partial Claims**: Claim vested portions at any time
- **PoolManager Integration**: Automatic schedule creation on reward claims
- **Reduces Sell Pressure**: Aligns long-term incentives

#### 5. LiquidityManager (Uniswap Operations - 409 lines)
Isolated liquidity handler:
- **Uniswap V2 Integration**: Add/remove liquidity operations
- **Callback Mechanism**: Notifies PoolManager after liquidity additions
- **Token Segregation**: Only explicit transfers, never touches user stakes
- **Blast-Radius Limitation**: Isolated architecture prevents cross-contamination
- **Treasury Management**: LP tokens sent to configured treasury address

---

## Quick Start

Below is a minimal end-to-end example to deploy contracts, create a pool, and stake.

### 1) Deploy Contracts

```ts
// Deploy PoolManager
const [deployer, user] = await ethers.getSigners();
const PoolManager = await ethers.getContractFactory("PoolManager");
const poolManager = await PoolManager.deploy();
await poolManager.waitForDeployment();

// Deploy VestingManager (optional)
const VestingManager = await ethers.getContractFactory("VestingManager");
const vestingManager = await VestingManager.deploy(poolManager.target);
await vestingManager.waitForDeployment();

// Deploy LiquidityManager
const LiquidityManager = await ethers.getContractFactory("LiquidityManager");
const liquidityManager = await LiquidityManager.deploy(
  UNISWAP_ROUTER_ADDRESS,
  TREASURY_ADDRESS
);
await liquidityManager.waitForDeployment();
```

### 2) Setup Tokens and Uniswap Pair

```ts
// Deploy or get existing ECM and USDT tokens
const ECM = await ethers.getContractFactory("MockERC20");
const ecm = await ECM.deploy("ECM", "ECM", ethers.parseEther("10000000"));
const usdt = await ECM.deploy("USDT", "USDT", ethers.parseUnits("10000000", 6));

// Create Uniswap V2 pair (using factory)
const factory = await ethers.getContractAt("IUniswapV2Factory", FACTORY_ADDRESS);
await factory.createPair(ecm.target, usdt.target);
const pairAddress = await factory.getPair(ecm.target, usdt.target);

// Add initial liquidity to pair (needed for pricing)
// ... add liquidity via router ...
```

### 3) Create Pool and Allocate Tokens

```ts
// Authorize contracts
await poolManager.setVestingManager(vestingManager.target);
await poolManager.addAuthorizedVestingManager(vestingManager.target);
await poolManager.addAuthorizedLiquidityManager(liquidityManager.target);

// Create pool with LINEAR reward strategy
const poolParams = {
  ecm: ecm.target,
  usdt: usdt.target,
  pair: pairAddress,
  penaltyReceiver: deployer.address, // Treasury for slashed tokens
  rewardStrategy: 0, // 0 = LINEAR, 1 = MONTHLY
  allowedStakeDurations: [
    30 * 24 * 60 * 60,  // 30 days
    90 * 24 * 60 * 60,  // 90 days
    180 * 24 * 60 * 60  // 180 days - users select from these durations
  ],
  vestingDuration: 180 * 24 * 60 * 60, // 6 months vesting
  vestRewardsByDefault: false,
  penaltyBps: 2500 // 25% penalty for early unstake
};

await poolManager.createPool(poolParams);
const poolId = 0;

// Allocate ECM for sale and rewards
await ecm.approve(poolManager.target, ethers.parseEther("1000000"));
await poolManager.allocateForSale(poolId, ethers.parseEther("500000"));
await poolManager.allocateForRewards(poolId, ethers.parseEther("100000"));

// Set reward rate (LINEAR strategy)
await poolManager.setLinearRewardRate(poolId, ethers.parseEther("1")); // 1 ECM/second
```

### 4) User Buy & Stake

```ts
// User buys ECM with USDT and auto-stakes
await usdt.connect(user).approve(poolManager.target, ethers.parseUnits("10000", 6));

await poolManager.connect(user).buyAndStake(
  poolId,
  ethers.parseUnits("10000", 6), // Max 10,000 USDT
  30 * 24 * 60 * 60, // 30-day stake duration
  IReferralVoucher.VoucherInput calldata voucherInput,
  bytes calldata voucherSignature
);

// Alternative: Buy exact ECM amount
await poolManager.connect(user).buyExactECMAndStake(
  poolId,
  ethers.parseEther("5000"), // Exactly 5000 ECM
  ethers.parseUnits("10000", 6), // Max USDT willing to spend
  30 * 24 * 60 * 60,
  IReferralVoucher.VoucherInput calldata voucherInput,
  bytes calldata voucherSignature
);
```

### 5) Claim Rewards & Unstake

```ts
// Check pending rewards
const pending = await poolManager.pendingRewards(poolId, user.address);

// Claim rewards only (without unstaking)
// Vesting behavior determined by pool configuration
await poolManager.connect(user).claimRewards(poolId);

// Unstake (auto-claims rewards)
await poolManager.connect(user).unstake(poolId);

// If pool has vesting enabled, claim from VestingManager
const vestingIds = await vestingManager.getUserVestingIds(user.address);
await vestingManager.connect(user).claimVested(vestingIds[0]);
```

### 6) Set Referrer After Purchase (New Feature)

```ts
// If user didn't provide referral code during purchase, they can add it later
// Requires valid EIP-712 voucher signature

// Option A: Direct call to ReferralModule
await referralModule.connect(user).setMyReferrer(
  {
    vid: voucherId,
    codeHash: ethers.keccak256(ethers.toUtf8Bytes("FRIEND2024")),
    owner: referrerAddress,
    directBps: 1000, // 10% (not used for late setting)
    transferOnUse: false,
    expiry: Math.floor(Date.now() / 1000) + 86400, // 24 hours
    maxUses: 100,
    nonce: 1
  },
  voucherSignature
);

// Option B: Delegated call via PoolManager (recommended for UX)
await poolManager.connect(user).setMyReferrer(voucherInput, voucherSignature);

// Note: No direct commission paid for late referrer setting
// Only affects future reward claims for multi-level commissions
```

---

---

## PoolManager Contract

### Core Features

#### 1. Token Sale & Auto-Staking
- **USDT→ECM Purchases**: Uses Uniswap V2 spot pricing from reserves
- **500 ECM Minimum**: All purchases must be multiples of 500 ECM
- **Single-Call UX**: `buyAndStake()` combines purchase and staking in one transaction
- **Slippage Protection**: `maxUsdtAmount` prevents overpaying due to price changes
- **Exact Amount Purchase**: `buyExactECMAndStake()` for precise ECM amounts

#### 2. Dual Reward Strategies

**LINEAR Strategy:**
- Constant reward rate per second (e.g., 1 ECM/sec)
- Smooth, predictable reward accrual
- Configurable rate via `setLinearRewardRate()`
- Automatic rate zeroing when rewards depleted

**MONTHLY Strategy:**
- Different reward rates per month (e.g., [1000, 2000, 3000] ECM/month)
- Rate-per-second distribution within each month
- Automatic month progression
- Ideal for incentive programs with changing rewards

#### 3. Early Unstaking with Penalties
- **Configurable Penalty**: Default 25% (2500 bps) of principal
- **Rewards Protected**: Only principal slashed, rewards remain intact
- **Penalty Receiver**: Slashed tokens sent to treasury/burn address
- **Maturity Check**: Penalty only applied if unstaked before `stakeDuration` expires

#### 4. Optional Reward Vesting
- **Linear Vesting**: Rewards vest linearly over configured duration
- **User Choice**: Pool can allow users to choose vesting vs immediate claim
- **VestingManager Integration**: Creates vesting schedules automatically
- **Reduced Sell Pressure**: Vesting aligns long-term incentives

#### 5. Comprehensive Analytics
10+ view functions for off-chain calculations:
- `calculateAPR()` - Annual Percentage Rate
- `calculateExpectedRewards()` - Projected rewards over time
- `calculateROI()` - Return on Investment
- `calculateTVL()` - Total Value Locked
- `getPoolAnalytics()` - Complete pool statistics
- `getUserAnalytics()` - User historical data

---

## PoolManager Data Structures

### Pool Struct
```solidity
struct Pool {
    // Core Identification
    uint32 id;                      // Unique pool identifier
    bool active;                    // Whether pool accepts new purchases/stakes
    
    // Token Configuration
    IERC20 ecm;                     // ECM token contract
    IERC20 usdt;                    // USDT payment token
    IUniswapV2Pair pair;            // Uniswap V2 pair for pricing
    
    // Penalty Configuration
    uint16 penaltyBps;              // Early unstake penalty (2500 = 25%)
    address penaltyReceiver;        // Receives slashed tokens
    
    // Token Allocation & Sale Tracking
    uint256 allocatedForSale;       // ECM allocated for public sale
    uint256 allocatedForRewards;    // ECM allocated for staking rewards
    uint256 sold;                   // Total ECM sold to users
    uint256 collectedUSDT;          // Total USDT collected from sales
    
    // Staking State
    uint256 totalStaked;            // Total ECM currently staked (equals sold)
    
    // Reward Distribution (accRewardPerShare Pattern)
    uint256 accRewardPerShare;      // Accumulated rewards per share (scaled 1e18)
    uint256 lastRewardTime;         // Last reward update timestamp
    
    // Reward Strategy Configuration
    RewardStrategy rewardStrategy;  // LINEAR, MONTHLY, or WEEKLY
    uint256 rewardRatePerSecond;    // For LINEAR strategy
    
    // Staking Duration Rules
    uint256[] allowedStakeDurations; // e.g., [30 days, 90 days, 180 days] - no minimum required
    uint256 maxDuration;             // Maximum staking duration
    
    // Vesting Configuration
    uint256 vestingDuration;         // Linear vesting period for rewards
    bool vestRewardsByDefault;       // Auto-vest vs user choice
    
    // Monthly/Weekly Reward Data
    uint256[] monthlyRewards;        // Monthly reward schedule
    uint256 monthlyRewardIndex;      // Current month index
    uint256 monthlyRewardStart;      // Month tracking start time
    uint256[] weeklyRewards;         // Weekly reward schedule
    uint256 weeklyRewardIndex;       // Current week index
    uint256 weeklyRewardStart;       // Week tracking start time
    
    // Liquidity Tracking (Two-Level)
    uint256 liquidityPoolOwedECM;   // Net ECM in LiquidityManager
    uint256 ecmMovedToLiquidity;    // ECM transferred to LiquidityManager
    uint256 usdtMovedToLiquidity;   // USDT transferred to LiquidityManager
    uint256 ecmAddedToUniswap;      // ECM added to Uniswap (via callback)
    uint256 usdtAddedToUniswap;     // USDT added to Uniswap (via callback)
    
    // Vesting & Rewards Tracking
    uint256 ecmVested;              // ECM sent to VestingManager
    uint256 rewardsPaid;            // Total rewards paid (immediate + vested)
    uint256 totalRewardsAccrued;    // Total rewards accrued (for capping)
    
    // Historical & Analytics
    uint256 poolCreatedAt;          // Pool creation timestamp
    uint256 totalPenaltiesCollected; // ECM from early unstakes
    uint256 peakTotalStaked;        // Highest totalStaked reached
    uint256 totalUniqueStakers;     // Unique staker count
    uint256 lifetimeStakeVolume;    // Cumulative ECM staked
    uint256 lifetimeUnstakeVolume;  // Cumulative ECM unstaked
}
```

### UserInfo Struct
```solidity
struct UserInfo {
    uint256 bought;              // Total ECM purchased (historical)
    uint256 staked;              // Currently staked ECM
    uint256 stakeStart;          // Current stake start timestamp
    uint256 stakeDuration;       // Selected lock duration
    
    // Reward Calculation (accRewardPerShare Pattern)
    uint256 rewardDebt;          // Reward debt for calculation
    uint256 pendingRewards;      // Accumulated unclaimed rewards
    
    // Historical & Analytics
    bool hasStaked;              // Ever staked in pool flag
    uint256 totalStaked;         // Lifetime total staked
    uint256 totalUnstaked;       // Lifetime total unstaked
    uint256 totalRewardsClaimed; // Lifetime rewards claimed
    uint256 totalPenaltiesPaid;  // Total penalties paid
    uint256 firstStakeTimestamp; // First stake timestamp
    uint256 lastActionTimestamp; // Last action timestamp
}
```

### PoolCreateParams Struct
```solidity
struct PoolCreateParams {
    address ecm;                     // ECM token address
    address usdt;                    // USDT token address
    address pair;                    // Uniswap V2 pair address
    address penaltyReceiver;         // Penalty receiver address
    RewardStrategy rewardStrategy;   // LINEAR, MONTHLY, or WEEKLY
    uint256[] allowedStakeDurations; // Allowed lock periods
    uint256 maxDuration;             // Maximum staking duration
    uint256 vestingDuration;         // Vesting duration (0 = none)
    bool vestRewardsByDefault;       // Auto-vest flag
    uint16 penaltyBps;               // Penalty in bps (0 = use default)
}
```

### UserInfo Struct
```solidity
struct UserInfo {
    uint256 bought;              // Historical tracking
    uint256 staked;              // Currently staked amount
    uint256 stakeStart;          // Stake start timestamp
    uint256 stakeDuration;       // Selected lock duration
    uint256 rewardDebt;          // For accRewardPerShare calculation
    uint256 pendingRewards;      // Accumulated unclaimed rewards
    
    // Analytics
    bool hasStaked;
    uint256 totalStaked;
    uint256 totalUnstaked;
    uint256 totalRewardsClaimed;
    uint256 totalPenaltiesPaid;
    uint256 firstStakeTimestamp;
    uint256 lastActionTimestamp;
}
```

---

## PoolManager Key Functions

### Admin Functions

#### Pool Management
```solidity
// Create new pool
function createPool(PoolCreateParams calldata params) external onlyOwner returns (uint256 poolId)

// Allocate ECM for sale and rewards
function allocateForSale(uint256 poolId, uint256 amount) external onlyOwner
function allocateForRewards(uint256 poolId, uint256 amount) external onlyOwner

// Activate/deactivate pool
function setPoolActive(uint256 poolId, bool active) external onlyOwner
```

#### Reward Configuration
```solidity
// LINEAR strategy - automatically calculates rate based on maxDuration
function setLinearRewardRate(uint256 poolId) external onlyOwner

// MONTHLY strategy
function setMonthlyRewards(uint256 poolId, uint256[] calldata monthlyAmounts) external onlyOwner

// WEEKLY strategy
function setWeeklyRewards(uint256 poolId, uint256[] calldata weeklyAmounts) external onlyOwner

// Update staking rules
function setAllowedStakeDurations(uint256 poolId, uint256[] calldata durations) external onlyOwner
function setPenaltyConfig(uint256 poolId, uint16 penaltyBps, address penaltyReceiver) external onlyOwner
function setVestingConfig(uint256 poolId, uint256 vestingDuration, bool vestByDefault) external onlyOwner
```

#### Contract Integration
```solidity
// Set VestingManager
function setVestingManager(address _vestingManager) external onlyOwner

// Set ReferralVoucher
function setReferralVoucher(address _referralVoucher) external onlyOwner

// Set ReferralModule
function setReferralModule(address _referralModule) external onlyOwner

// Authorize LiquidityManager
function addAuthorizedLiquidityManager(address manager) external onlyOwner
function removeAuthorizedLiquidityManager(address manager) external onlyOwner

// Transfer to LiquidityManager
function transferToLiquidityManager(
    uint256 poolId,
    address liquidityManager,
    uint256 ecmAmount,
    uint256 usdtAmount
) external onlyOwner

// Callback from LiquidityManager (called by authorized contracts)
function recordLiquidityAdded(
    uint256 poolId,
    uint256 ecmAmount,
    uint256 usdtAmount
) external

// Refill pool from LiquidityManager (called by authorized contracts)
function refillPoolManager(uint256 poolId, uint256 ecmAmount) external
```

#### Emergency & Governance
```solidity
// Emergency token recovery
function emergencyRecoverTokens(address token, uint256 amount, address to) external onlyOwner

// Pause/unpause operations
function pause() external onlyOwner
function unpause() external onlyOwner
```

### User Functions

#### Buying & Staking
```solidity
// Buy with max USDT amount (referral optional)
function buyAndStake(
    uint256 poolId,
    uint256 maxUsdtAmount,
    uint256 selectedStakeDuration,
    IReferralVoucher.VoucherInput calldata voucherInput,
    bytes calldata voucherSignature
) external nonReentrant whenNotPaused

// Buy exact ECM amount (referral optional)
function buyExactECMAndStake(
    uint256 poolId,
    uint256 exactEcmAmount,
    uint256 maxUsdtAmount,
    uint256 selectedStakeDuration,
    IReferralVoucher.VoucherInput calldata voucherInput,
    bytes calldata voucherSignature
) external nonReentrant whenNotPaused
```

#### Unstaking & Claiming
```solidity
// Unstake and claim all rewards
function unstake(uint256 poolId) external nonReentrant

// Claim rewards only (without unstaking)
// Vesting behavior determined by pool.vestRewardsByDefault
function claimRewards(uint256 poolId) external nonReentrant
```

### View Functions

#### Pool Information
```solidity
function getPoolInfo(uint256 poolId) external view returns (Pool memory)
function getUserInfo(uint256 poolId, address user) external view returns (UserInfo memory)
function pendingRewards(uint256 poolId, address user) public view returns (uint256)
```

#### Pricing
```solidity
// Get spot price from Uniswap
function getPriceSpot(uint256 poolId) public view returns (
    uint256 usdtPerEcm,    // Price in USDT per ECM (scaled by 1e18)
    uint256 reserveECM,    // ECM reserve in pair
    uint256 reserveUSDT    // USDT reserve in pair
)

// Estimate costs
function getRequiredUSDTForExactECM(uint256 poolId, uint256 exactEcm) external view returns (uint256 usdtRequired)
function estimateECMForUSDT(uint256 poolId, uint256 usdtAmount) external view returns (uint256 ecmEstimate)

// Pool balance breakdown
function getPoolBalanceStatus(uint256 poolId) external view returns (
    uint256 totalAllocated,
    uint256 soldToUsers,
    uint256 currentlyStaked,
    uint256 movedToLiquidity,
    uint256 liquidityOwedECM,
    uint256 addedToUniswap,
    uint256 vested,
    uint256 rewardsPaid,
    uint256 availableInContract,
    uint256 deficit
)
```

#### Analytics
```solidity
// APR calculation (works for all strategies: LINEAR, MONTHLY, WEEKLY)
// periodsToProject: years for LINEAR (scaled 1e18), months for MONTHLY, weeks for WEEKLY
function calculateAPR(uint256 poolId, uint256 periodsToProject) public view returns (uint256 apr)

// User projections
function calculateExpectedRewards(
    uint256 poolId,
    address user,
    uint256 durationSeconds
) external view returns (uint256 expectedRewards)

function calculateROI(
    uint256 poolId,
    address user,
    uint256 durationSeconds,
    uint256 ecmPriceInUsdt
) external view returns (uint256 roi)

// Pool metrics
function calculateTVL(uint256 poolId, uint256 ecmPriceInUsdt) external view returns (uint256 tvl)
function calculateUtilizationRate(uint256 poolId) external view returns (uint256 utilizationRate)
function calculateRewardDepletionTime(uint256 poolId) external view returns (
    uint256 depletionTimestamp,
    uint256 daysRemaining,
    bool isInfinite
)

// Comprehensive analytics
function getPoolAnalytics(uint256 poolId, uint256 ecmPriceInUsdt) external view returns (
    uint256 poolAge,
    uint256 totalUniqueStakers,
    uint256 totalPenaltiesCollected,
    uint256 peakTotalStaked,
    uint256 lifetimeStakeVolume,
    uint256 lifetimeUnstakeVolume,
    uint256 currentTVL
)

function getUserAnalytics(uint256 poolId, address user) external view returns (
    bool hasStaked,
    uint256 firstStakeTimestamp,
    uint256 lastActionTimestamp,
    uint256 totalStaked,
    uint256 totalUnstaked,
    uint256 totalRewardsClaimed,
    uint256 totalPenaltiesPaid,
    uint256 accountAge
)

function calculateUnstakePenalty(uint256 poolId, address user) external view returns (
    bool willBePenalized,
    uint256 penaltyAmount,
    uint256 amountReceived,
    uint256 timeUntilMaturity
)
```

---

## ReferralVoucher Contract

### Purpose
**ReferralVoucher** implements EIP-712 typed signature verification for off-chain referral codes. It allows authorized issuers (backend servers) to generate cryptographically signed vouchers that users can redeem when purchasing ECM tokens. This enables secure, scalable referral code management without storing codes on-chain.

### Core Features

#### EIP-712 Signature Verification
- **Typed Structured Data**: Uses EIP-712 standard for human-readable signatures
- **Domain Separation**: Prevents cross-chain and cross-contract replay attacks
- **Off-Chain Generation**: Backend generates signatures, on-chain verification
- **No On-Chain Storage**: Referral codes never stored on blockchain (gas efficient)

#### Usage Tracking & Limits
- **Single-Use Vouchers**: For one-time promotions or unique codes
- **Multi-Use Vouchers**: With configurable `maxUses` limit (e.g., 100 redemptions)
- **Unlimited Vouchers**: Perfect for persistent referral codes (`maxUses = 0`)
- **Usage Counter**: Tracks redemptions per voucher ID

#### Security Features
- **Issuer Whitelist**: Only authorized addresses can sign valid vouchers
- **Expiry Enforcement**: Vouchers have timestamp-based expiration
- **Revocation Support**: Admin can cancel specific voucher IDs
- **onlyPoolManager Modifier**: Prevents direct user calls, only PoolManager can verify

### Data Structures

#### VoucherInput Struct
```solidity
struct VoucherInput {
    bytes32 vid;           // Unique voucher ID = keccak256(codeHash, owner, nonce)
    bytes32 codeHash;      // keccak256 of referral code string (e.g., "PROMO2024")
    address owner;         // Referrer who owns this code
    uint16 directBps;      // Direct commission rate in basis points (500 = 5%)
    bool transferOnUse;    // true = immediate transfer, false = accrued
    uint64 expiry;         // Expiration timestamp (block.timestamp < expiry)
    uint32 maxUses;        // Usage limit (0 = unlimited)
    uint256 nonce;         // Unique nonce for generating vid
}
```

#### VoucherResult Struct (Return Value)
```solidity
struct VoucherResult {
    address owner;         // Referrer address
    bytes32 codeHash;      // Code identifier
    uint16 directBps;      // Commission rate
    bool transferOnUse;    // Payment mode
    uint32 usesRemaining;  // Remaining uses (or max if unlimited)
}
```

### EIP-712 Type Definition
```solidity
// Type hash for voucher
bytes32 constant VOUCHER_TYPEHASH = keccak256(
    "ReferralVoucher(bytes32 vid,bytes32 codeHash,address owner,uint16 directBps,bool transferOnUse,uint64 expiry,uint32 maxUses,uint256 nonce)"
);

// Domain separator (per-chain, per-contract)
EIP712("ReferralVoucher", "1")
```

### Key Functions

#### Admin Functions
```solidity
// Manage authorized issuers (backend signing keys)
function addIssuer(address issuer) external onlyOwner
function removeIssuer(address issuer) external onlyOwner

// Revoke specific voucher ID (emergency)
function revokeVoucher(bytes32 vid) external onlyOwner

// Set PoolManager address (one-time setup)
function setPoolManager(address _poolManager) external onlyOwner
```

#### PoolManager Integration
```solidity
// Verify and consume voucher (only callable by PoolManager)
function verifyAndConsume(
    VoucherInput calldata voucherInput,
    bytes calldata signature,
    address redeemer
) external onlyPoolManager returns (VoucherResult memory)
```

**Verification Flow:**
1. Check `block.timestamp < expiry`
2. Check `!voucherRevoked[vid]`
3. Check `voucherUses[vid] < maxUses` (if `maxUses > 0`)
4. Recover signer from EIP-712 signature
5. Validate `isIssuer[signer] == true`
6. Increment `voucherUses[vid]++`
7. Return `VoucherResult` struct

### Off-Chain Voucher Generation (Backend)

#### TypeScript Example with ethers v6
```typescript
import { ethers } from 'ethers';

// EIP-712 Domain
const domain = {
  name: 'ReferralVoucher',
  version: '1',
  chainId: 1124, // ECM testnet
  verifyingContract: '0x...' // ReferralVoucher contract address
};

// EIP-712 Types
const types = {
  ReferralVoucher: [
    { name: 'vid', type: 'bytes32' },
    { name: 'codeHash', type: 'bytes32' },
    { name: 'owner', type: 'address' },
    { name: 'directBps', type: 'uint16' },
    { name: 'transferOnUse', type: 'bool' },
    { name: 'expiry', type: 'uint64' },
    { name: 'maxUses', type: 'uint32' },
    { name: 'nonce', type: 'uint256' }
  ]
};

// Generate voucher
async function generateVoucher(
  issuerSigner: ethers.Signer,
  referralCode: string,
  referrerAddress: string,
  directBps: number,
  transferOnUse: boolean,
  expiryTimestamp: number,
  maxUses: number,
  nonce: bigint
) {
  // Hash the referral code
  const codeHash = ethers.keccak256(ethers.toUtf8Bytes(referralCode));
  
  // Generate unique voucher ID
  const vid = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'address', 'uint256'],
      [codeHash, referrerAddress, nonce]
    )
  );
  
  // Voucher data
  const voucher = {
    vid,
    codeHash,
    owner: referrerAddress,
    directBps,
    transferOnUse,
    expiry: expiryTimestamp,
    maxUses,
    nonce
  };
  
  // Sign with EIP-712
  const signature = await issuerSigner.signTypedData(domain, types, voucher);
  
  return { voucher, signature };
}

// Usage example
const issuer = new ethers.Wallet('0x...private key', provider);
const { voucher, signature } = await generateVoucher(
  issuer,
  'PROMO2024',              // Referral code
  '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb', // Referrer address
  500,                      // 5% commission
  false,                    // Accrued mode
  Math.floor(Date.now() / 1000) + 86400 * 30, // 30 days expiry
  0,                        // Unlimited uses
  BigInt(12345)             // Unique nonce
);
```

### Frontend Integration (User Redemption)

#### React/TypeScript Example
```typescript
import { ethers } from 'ethers';

// User buys with referral voucher
async function buyWithReferral(
  poolManagerContract: ethers.Contract,
  poolId: number,
  maxUsdtAmount: bigint,
  stakeDuration: number,
  voucher: VoucherInput,
  signature: string
) {
  // Call buyAndStake with voucher and signature
  const tx = await poolManagerContract.buyAndStake(
    poolId,
    maxUsdtAmount,
    stakeDuration,
    voucher,  // VoucherInput struct
    signature // EIP-712 signature from backend
  );
  
  await tx.wait();
  console.log('Purchase successful with referral!');
}
```

### Security Considerations

#### Protection Against Attacks
- **Replay Protection**: Each voucher has unique `vid` (includes nonce)
- **Cross-Chain Protection**: Domain separator includes `chainId`
- **Cross-Contract Protection**: Domain separator includes `verifyingContract`
- **Expiry**: Vouchers automatically invalid after `expiry` timestamp
- **Usage Limits**: `maxUses` prevents unlimited redemptions of single-use codes
- **Issuer Whitelist**: Only authorized backend keys can sign valid vouchers
- **Revocation**: Admin can emergency-cancel specific vouchers

#### Gas Optimization
- **No On-Chain Storage**: Referral codes never stored on-chain
- **Signature Verification**: Only ~5,000 gas per verification
- **Stateless Vouchers**: No need to query blockchain for code validity

### Events

```solidity
event IssuerAdded(address indexed issuer);
event IssuerRemoved(address indexed issuer);
event VoucherRevoked(bytes32 indexed vid);
event VoucherVerified(
    bytes32 indexed vid,
    bytes32 indexed codeHash,
    address indexed owner,
    address redeemer,
    uint32 usesRemaining
);
```

---

## ReferralModule Contract

### Purpose
**ReferralModule** implements a sophisticated two-tier commission system for referrals:
1. **Tier 1 (Direct Commission)**: Immediate or accrued payments on purchases (based on principal)
2. **Tier 2 (Multi-Level Commission)**: Merkle-based distribution on reward claims (up to 10 levels)

This design optimizes gas efficiency by paying direct commissions immediately while deferring multi-level calculations to off-chain systems with Merkle proof verification.

### Core Features

#### Two-Tier Commission Model

##### Tier 1: Direct Commission (On Purchase)
- **Trigger**: When user stakes ECM via `buyAndStake()`
- **Basis**: Staked amount (principal)
- **Rate**: Configured per voucher (`directBps`, max 20% = 2000 bps)
- **Payment Modes**:
  - **Immediate (`transferOnUse=true`)**: ECM transferred to referrer instantly
  - **Accrued (`transferOnUse=false`)**: Accumulates in `directAccrued` mapping, referrer withdraws later
- **Gas Cost**: ~30,000 gas (single transfer or state update)

##### Tier 2: Multi-Level Commission (On Reward Claims)
- **Trigger**: When user claims staking rewards
- **Basis**: Reward amount (NOT principal)
- **Levels**: Up to 10 referral chain levels (configurable per pool)
- **Rate**: Different per level (e.g., L1=5%, L2=3%, L3=2%)
- **Distribution**: Off-chain Merkle tree computation, on-chain proof verification
- **Gas Cost**: ~50,000 gas per claim (regardless of referral chain length)

#### Anti-Gaming Rules
- **No Self-Referral**: `buyer != referrer` enforced
- **No Cyclic Referrals**: If A refers B, B cannot refer A (2-person loop blocked)
- **Immutable Referrer**: Once set, `referrerOf[user]` cannot be changed
- **Max 10 Levels**: Referral chain depth limited to prevent unbounded loops
- **Total ML Commission Cap**: Sum of all multi-level rates ≤ 50% (5000 bps)
- **Direct Commission Cap**: `directBps` ≤ 20% (2000 bps)

### Data Structures

#### Referral Relationships
```solidity
// Immutable buyer → referrer mapping
mapping(address => address) public referrerOf;

// Accrued direct commissions (for transferOnUse=false mode)
mapping(address => uint256) public directAccrued;
```

#### Pool-Level Multi-Level Config
```solidity
// Multi-level commission rates per pool (up to 10 levels)
// Example: [500, 300, 200, 100, 100, 50, 50, 25, 25, 25]
//          = [5%, 3%, 2%, 1%, 1%, 0.5%, 0.5%, 0.25%, 0.25%, 0.25%]
mapping(uint256 => uint16[]) public poolLevelConfig;
```

#### Merkle Distribution (Tier 2)
```solidity
struct ReferralPayoutRoot {
    bytes32 merkleRoot;       // Root of Merkle tree
    uint256 totalAmount;      // Total ECM allocated for this epoch
    uint256 expiry;           // Expiration timestamp
    bool withdrawn;           // Whether unclaimed tokens recovered
}

// Epoch ID → Payout root
mapping(uint256 => ReferralPayoutRoot) public payoutRoots;

// Track claims: epochId → user → claimed
mapping(uint256 => mapping(address => bool)) public claimedInEpoch;
```

### Key Functions

#### Direct Commission (Tier 1)

##### Record Purchase & Pay Direct
```solidity
function recordPurchaseAndPayDirect(
    bytes32 codeHash,
    address buyer,
    address referrer,
    uint256 poolId,
    uint256 stakedAmount,
    IERC20 token,
    uint16 directBps,
    bool transferOnUse
) external onlyPoolManager
```

**Process:**
1. Link referrer if first purchase: `referrerOf[buyer] = referrer`
2. Calculate commission: `directAmount = stakedAmount * directBps / 10000`
3. If `transferOnUse`:
   - Transfer ECM to referrer immediately
   - Emit `DirectCommissionPaid`
4. Else:
   - Accumulate: `directAccrued[referrer] += directAmount`
   - Emit `DirectCommissionAccrued`

##### Withdraw Accrued Direct Commissions
```solidity
function withdrawDirectAccrual(uint256 amount) external nonReentrant
```
- **Caller**: Referrer
- **Purpose**: Withdraw accumulated direct commissions
- **Process**:
  1. Verify `directAccrued[msg.sender] >= amount`
  2. Deduct: `directAccrued[msg.sender] -= amount`
  3. Transfer ECM to msg.sender

#### Multi-Level Commission (Tier 2)

##### Record Reward Claim Event (On-Chain)
```solidity
function recordRewardClaimEvent(
    address claimant,
    uint256 poolId,
    uint256 rewardAmount
) external onlyPoolManager
```
- **Purpose**: Emit event for off-chain indexer to process
- **Emits**: `RewardClaimRecorded(claimant, poolId, rewardAmount, block.timestamp)`

##### Submit Merkle Root (Admin/Backend)
```solidity
function submitReferralPayoutRoot(
    uint256 epochId,
    address token,
    uint256 totalAmount,
    bytes32 merkleRoot,
    uint256 expiry
) external onlyOwner
```
- **Purpose**: Upload computed Merkle root for epoch-based distribution
- **Process**:
  1. Transfer `totalAmount` ECM from admin to ReferralModule
  2. Store `ReferralPayoutRoot` struct
  3. Emit `ReferralPayoutRootSubmitted`

##### Claim Multi-Level Commission (User)
```solidity
function claimReferral(
    uint256 epochId,
    address token,
    uint256 amount,
    bytes32[] calldata proof
) external nonReentrant
```
- **Purpose**: Users claim their multi-level commissions with Merkle proof
- **Process**:
  1. Verify proof against `payoutRoots[epochId].merkleRoot`
  2. Leaf = `keccak256(abi.encodePacked(msg.sender, token, amount, epochId))`
  3. Check: `!claimedInEpoch[epochId][msg.sender]`
  4. Check: `block.timestamp < expiry`
  5. Mark claimed: `claimedInEpoch[epochId][msg.sender] = true`
  6. Transfer ECM to msg.sender
  7. Emit `ReferralPayoutClaimed`

#### Configuration

```solidity
// Set multi-level commission rates per pool
function setPoolLevelConfig(
    uint256 poolId,
    uint16[] calldata mlBps
) external onlyOwner

// Set PoolManager address
function setPoolManager(address _poolManager) external onlyOwner

// Fund contract with ECM for commissions
function fundContract(uint256 amount) external
```

### Off-Chain Multi-Level Calculation (Backend)

#### Algorithm
1. **Listen to Events**: Monitor `RewardClaimRecorded(claimant, poolId, rewardAmount)`
2. **Walk Referral Chain**:
   ```
   claimant → referrer1 → referrer2 → ... → referrer10
   ```
3. **Calculate Commissions**:
   ```typescript
   for (let level = 0; level < 10; level++) {
     const referrer = referralChain[level];
     if (!referrer) break;
     
     const mlBps = poolLevelConfig[poolId][level];
     const commission = rewardAmount * mlBps / 10000;
     
     commissions.push({
       beneficiary: referrer,
       token: ecmAddress,
       amount: commission,
       epochId: currentEpochId
     });
   }
   ```
4. **Build Merkle Tree**:
   ```typescript
   const leaves = commissions.map(c => 
     ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
       ['address', 'address', 'uint256', 'uint256'],
       [c.beneficiary, c.token, c.amount, c.epochId]
     ))
   );
   
   const tree = new MerkleTree(leaves.sort(), keccak256, { sortPairs: true });
   const root = tree.getRoot();
   ```
5. **Submit Root**: Call `submitReferralPayoutRoot(epochId, token, totalAmount, root, expiry)`
6. **Provide Proofs**: Generate Merkle proofs for each beneficiary via API

#### TypeScript Example
```typescript
import { MerkleTree } from 'merkletreejs';
import { ethers } from 'ethers';

interface Commission {
  beneficiary: string;
  token: string;
  amount: bigint;
  epochId: number;
}

function calculateMultiLevelCommissions(
  claimant: string,
  rewardAmount: bigint,
  poolId: number,
  poolLevelConfig: number[], // [500, 300, 200, ...]
  referrerOf: Map<string, string> // buyer → referrer mapping
): Commission[] {
  const commissions: Commission[] = [];
  let current = claimant;
  
  for (let level = 0; level < 10 && level < poolLevelConfig.length; level++) {
    const referrer = referrerOf.get(current);
    if (!referrer) break;
    
    const mlBps = poolLevelConfig[level];
    const commission = (rewardAmount * BigInt(mlBps)) / 10000n;
    
    if (commission > 0) {
      commissions.push({
        beneficiary: referrer,
        token: ecmAddress,
        amount: commission,
        epochId: currentEpochId
      });
    }
    
    current = referrer;
  }
  
  return commissions;
}

function buildMerkleTree(commissions: Commission[]): {
  root: string;
  proofs: Map<string, string[]>;
} {
  const leaves = commissions.map(c => 
    ethers.solidityPackedKeccak256(
      ['address', 'address', 'uint256', 'uint256'],
      [c.beneficiary, c.token, c.amount, c.epochId]
    )
  ).sort();
  
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const root = tree.getHexRoot();
  
  const proofs = new Map<string, string[]>();
  commissions.forEach((c, i) => {
    const proof = tree.getHexProof(leaves[i]);
    proofs.set(c.beneficiary, proof);
  });
  
  return { root, proofs };
}
```

### Integration Flow Example

#### Complete Purchase with Direct Commission
```solidity
// User calls PoolManager.buyAndStake() with voucher
// PoolManager:
1. Verifies voucher via ReferralVoucher.verifyAndConsume()
2. Transfers USDT from user
3. Updates pool accounting (sold, totalStaked, etc.)
4. Calls ReferralModule.recordPurchaseAndPayDirect()
   - Calculates direct commission (e.g., 1000 ECM * 5% = 50 ECM)
   - If transferOnUse: Transfers 50 ECM to referrer
   - Else: Accumulates in directAccrued[referrer]
5. Emits BoughtAndStaked event
```

#### Complete Reward Claim with Multi-Level Commission
```solidity
// User calls PoolManager.claimRewards()
// PoolManager:
1. Calculates pending rewards (e.g., 500 ECM)
2. Transfers rewards to user (or creates vesting schedule)
3. Calls ReferralModule.recordRewardClaimEvent(user, poolId, 500 ECM)
   - Emits RewardClaimRecorded event

// Off-chain backend:
4. Listens to RewardClaimRecorded event
5. Calculates multi-level commissions:
   - L1 referrer: 500 * 5% = 25 ECM
   - L2 referrer: 500 * 3% = 15 ECM
   - L3 referrer: 500 * 2% = 10 ECM
6. Builds Merkle tree with all commissions for epoch
7. Calls ReferralModule.submitReferralPayoutRoot()

// Users (referrers):
8. Query backend API for their commission amount and proof
9. Call ReferralModule.claimReferral(epochId, token, amount, proof)
10. Receive multi-level commission ECM
```

### Gas Efficiency Analysis

#### Direct Commission (Tier 1)
- **Immediate Transfer**: ~30,000 gas (SSTORE + CALL)
- **Accrued Mode**: ~20,000 gas (single SSTORE)
- **Withdraw**: ~25,000 gas per withdrawal

#### Multi-Level Commission (Tier 2)
- **Record Event**: ~1,500 gas (emit only)
- **Submit Root**: ~45,000 gas (one-time per epoch)
- **Claim with Proof**: ~50,000 gas per claim
  - Merkle verification: ~20,000 gas (log₂N hashes)
  - State updates: ~20,000 gas
  - Transfer: ~10,000 gas

**Comparison with Naive Approach:**
- Naive: ~200,000 gas per reward claim (10 transfers in loop)
- Merkle: ~50,000 gas per claim (75% reduction)
- **Savings**: ~150,000 gas per claim with 10-level referrals

### Events

```solidity
event ReferrerLinked(address indexed buyer, address indexed referrer, bytes32 indexed codeHash);
event DirectCommissionPaid(address indexed referrer, uint256 amount, address token);
event DirectCommissionAccrued(address indexed referrer, uint256 amount);
event DirectCommissionWithdrawn(address indexed referrer, uint256 amount);

event RewardClaimRecorded(
    address indexed claimant,
    uint256 indexed poolId,
    uint256 rewardAmount,
    uint256 timestamp
);

event ReferralPayoutRootSubmitted(
    uint256 indexed epochId,
    address indexed token,
    bytes32 merkleRoot,
    uint256 totalAmount,
    uint256 expiry
);

event ReferralPayoutClaimed(
    uint256 indexed epochId,
    address indexed claimer,
    address token,
    uint256 amount
);
```

---

## LiquidityManager Contract

### Purpose
**LiquidityManager** is an isolated contract dedicated to managing Uniswap V2 liquidity operations. It receives explicit token transfers from the PoolManager and adds liquidity to ECM/USDT pairs. This separation ensures that liquidity operations cannot accidentally touch user-staked tokens.

### Core Features

#### Isolated Architecture
- **Single Responsibility**: Only handles Uniswap V2 liquidity additions/removals
- **Explicit Transfers**: Receives tokens via direct transfers (never sweeps from PoolManager)
- **Blast-Radius Limitation**: Security issues isolated from main PoolManager contract
- **Callback Integration**: Notifies PoolManager after successful liquidity additions

#### Access Control
- **Owner-Only Operations**: All liquidity functions restricted to contract owner (multisig recommended)
- **No User Interaction**: Users never directly interact with this contract
- **PoolManager Integration**: Only PoolManager can trigger liquidity callbacks

### Data Structures

#### AddLiquidityParams Struct
```solidity
struct AddLiquidityParams {
    address tokenA;           // First token (ECM)
    address tokenB;           // Second token (USDT)
    uint256 amountADesired;   // Desired ECM amount
    uint256 amountBDesired;   // Desired USDT amount
    uint256 amountAMin;       // Minimum ECM (slippage protection)
    uint256 amountBMin;       // Minimum USDT (slippage protection)
    address to;               // LP token recipient
    uint256 deadline;         // Transaction deadline
}
```

### Key Functions

#### Add Liquidity
```solidity
function addLiquidity(AddLiquidityParams calldata params) external onlyOwner returns (
    uint256 amountA,
    uint256 amountB,
    uint256 liquidity
)
```
- **Purpose**: Adds liquidity to Uniswap V2 pair
- **Process**:
  1. Approves tokens for Uniswap Router
  2. Calls `router.addLiquidity()` with parameters
  3. Triggers callback to PoolManager if configured
  4. Returns actual amounts used and LP tokens minted

#### Remove Liquidity
```solidity
function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
) external onlyOwner returns (uint256 amountA, uint256 amountB)
```
- **Purpose**: Removes liquidity from Uniswap V2 pair
- **Process**: Burns LP tokens, returns underlying tokens to specified recipient

#### Emergency Token Recovery
```solidity
function recoverTokens(address token, uint256 amount, address to) external onlyOwner
```
- **Purpose**: Recover mistakenly sent tokens
- **Safety**: Only callable by owner

#### Set Callback Contract
```solidity
function setCallbackContract(address _callbackContract) external onlyOwner
```
- **Purpose**: Configure PoolManager address for liquidity addition callbacks
- **Integration**: Allows PoolManager to track liquidity additions

### Integration with PoolManager

#### Transfer Flow
1. **Admin Action**: PoolManager owner calls `transferToLiquidityManager(ecmAmount, usdtAmount)`
2. **Token Transfer**: PoolManager transfers ECM and USDT to LiquidityManager
3. **Liquidity Addition**: LiquidityManager owner calls `addLiquidity()` with received tokens
4. **Callback**: LiquidityManager notifies PoolManager via `onLiquidityAdded()` callback
5. **Accounting Update**: PoolManager updates internal liquidity tracking

#### Security Guarantees
- **Token Segregation**: Only explicitly designated `liquidityReserve` tokens can be transferred
- **User Protection**: User-staked tokens (`totalStaked`) are NEVER accessible
- **Audit Trail**: All transfers logged via `LiquidityTransferred` events

### Usage Example

```solidity
// 1. PoolManager: Transfer tokens to LiquidityManager
await poolManager.transferToLiquidityManager(
    ethers.parseEther("10000"), // 10,000 ECM
    ethers.parseUnits("5000", 6), // 5,000 USDT (6 decimals)
    liquidityManagerAddress
);

// 2. LiquidityManager: Add liquidity
const params = {
    tokenA: ecmAddress,
    tokenB: usdtAddress,
    amountADesired: ethers.parseEther("10000"),
    amountBDesired: ethers.parseUnits("5000", 6),
    amountAMin: ethers.parseEther("9500"), // 5% slippage
    amountBMin: ethers.parseUnits("4750", 6),
    to: treasuryAddress,
    deadline: Math.floor(Date.now() / 1000) + 3600
};

await liquidityManager.addLiquidity(params);
```

---

## VestingManager Contract

### Purpose
**VestingManager** handles linear vesting schedules for reward tokens. When users claim rewards from PoolManager, rewards can optionally be vested over a configured duration (e.g., 6 months) to reduce sell pressure and align long-term incentives.

### Core Features

#### Linear Vesting Model
- **Pro-Rata Release**: Tokens unlock linearly over time
- **Immediate Start**: Vesting begins at `startTime` (typically claim time)
- **Claimable Anytime**: Users can claim vested portions at any time
- **Multiple Schedules**: Users can have multiple independent vesting schedules

#### Integration with PoolManager
- **Automatic Creation**: PoolManager creates vesting schedules when rewards claimed
- **Token Custody**: VestingManager holds tokens during vesting period
- **No Admin Intervention**: Fully automated once configured

### Data Structures

#### VestingSchedule Struct
```solidity
struct VestingSchedule {
    address beneficiary;    // User who will receive tokens
    uint256 totalAmount;    // Total tokens being vested
    uint256 startTime;      // Vesting start timestamp
    uint256 duration;       // Vesting duration in seconds
    uint256 claimed;        // Amount already claimed by user
}
```

### Key Functions

#### Create Vesting Schedule
```solidity
function createVesting(
    address beneficiary,
    uint256 amount,
    uint256 startTime,
    uint256 duration
) external onlyAuthorized returns (uint256 vestingId)
```
- **Caller**: Only PoolManager can call (via `onlyAuthorized` modifier)
- **Purpose**: Creates new vesting schedule for user rewards
- **Returns**: Unique `vestingId` for tracking
- **Process**:
  1. Receives tokens from PoolManager
  2. Creates `VestingSchedule` struct
  3. Adds to user's vesting list
  4. Emits `VestingCreated` event

#### Claim Vested Tokens
```solidity
function claimVested(uint256 vestingId) external nonReentrant
```
- **Caller**: User (beneficiary)
- **Purpose**: Claim unlocked tokens from vesting schedule
- **Process**:
  1. Calculate vested amount: `(totalAmount * elapsed) / duration`
  2. Subtract already claimed: `claimable = vested - claimed`
  3. Update `claimed` amount
  4. Transfer claimable tokens to beneficiary

#### View Vesting Info
```solidity
function getVestingSchedule(uint256 vestingId) external view returns (VestingSchedule memory)
function getUserVestingIds(address user) external view returns (uint256[] memory)
function calculateVested(uint256 vestingId) external view returns (uint256)
function calculateClaimable(uint256 vestingId) external view returns (uint256)
```

### Vesting Calculation Examples

#### Scenario 1: Halfway Through
- **Total Amount**: 10,000 ECM
- **Duration**: 180 days (6 months)
- **Elapsed**: 90 days (3 months)
- **Vested**: `10,000 * 90 / 180 = 5,000 ECM`
- **Already Claimed**: 2,000 ECM
- **Claimable**: `5,000 - 2,000 = 3,000 ECM`

#### Scenario 2: Fully Vested
- **Total Amount**: 5,000 ECM
- **Duration**: 180 days
- **Elapsed**: 200 days (> duration)
- **Vested**: `5,000 ECM` (100%)
- **Already Claimed**: 4,500 ECM
- **Claimable**: `5,000 - 4,500 = 500 ECM`

### Integration Flow

#### PoolManager → VestingManager
1. **User Claims Rewards**: User calls `claimRewards(poolId)` on PoolManager
2. **Check Vesting Config**: PoolManager checks `pool.vestRewardsByDefault` or user preference
3. **Transfer to VestingManager**: PoolManager transfers reward tokens to VestingManager
4. **Create Schedule**: PoolManager calls `vestingManager.createVesting()` with:
   - Beneficiary: User address
   - Amount: Reward amount
   - StartTime: `block.timestamp`
   - Duration: `pool.vestingDuration`
5. **Emit Event**: `RewardsVested(user, poolId, amount, vestingId)`

#### User Claims from VestingManager
1. **Check Vested**: User queries `calculateClaimable(vestingId)`
2. **Claim Tokens**: User calls `claimVested(vestingId)`
3. **Receive ECM**: Unlocked tokens transferred to user wallet
4. **Repeat**: User can claim multiple times as more tokens vest

### Configuration

#### Pool-Level Settings (PoolManager)
```solidity
struct Pool {
    // ...
    uint64 vestingDuration;      // e.g., 180 days (6 months)
    bool vestRewardsByDefault;   // Auto-vest all rewards if true
}
```

#### User Preferences
```solidity
// Users can opt-in/opt-out of vesting per pool
mapping(address => mapping(uint256 => bool)) public userVestingPreference;
```

### Usage Example

```solidity
// User claims rewards (vesting enabled)
await poolManager.claimRewards(0); // poolId = 0

// VestingManager automatically receives tokens and creates schedule
// Returns vestingId via event: RewardsVested(user, 0, 5000e18, vestingId=1)

// Wait 3 months...
const claimable = await vestingManager.calculateClaimable(1); // vestingId = 1
console.log(`Claimable: ${ethers.formatEther(claimable)} ECM`);

// Claim vested tokens
await vestingManager.claimVested(1);
```

---

## Testing

Comprehensive test coverage includes:

### Test Suite Status: ✅ 403 TOTAL TESTS PASSING across 8 essential test files

### PoolManager Tests
- **Token Sales**: USDT→ECM purchases with Uniswap pricing
- **Auto-Staking**: Single-call `buyAndStake()` flow
- **Reward Strategies**: LINEAR and MONTHLY distribution accuracy
- **Early Unstaking**: Principal slashing (25% default)
- **Analytics**: APR, ROI, expected rewards calculations
- **Edge Cases**: Price manipulation, rounding errors, overflow protection

### LiquidityManager Tests
- **Liquidity Addition**: Successful Uniswap V2 operations
- **Callback Integration**: PoolManager notification after additions
- **Access Control**: Owner-only enforcement
- **Token Recovery**: Emergency recovery mechanisms
- **Slippage Protection**: Min amount validation

### VestingManager Tests
- **Vesting Creation**: Correct schedule initialization
- **Linear Unlocking**: Pro-rata token release over time
- **Partial Claims**: Multiple claims during vesting period
- **Edge Cases**: Immediate claim, fully vested, multiple schedules
- **Access Control**: Only authorized contracts can create schedules

### Integration Tests
- **End-to-End Flow**: Buy → Stake → Claim → Vest → Unlock
- **Multi-User Scenarios**: Concurrent staking, reward distribution
- **Liquidity Operations**: Transfer → Add → Callback flow
- **Emergency Scenarios**: Pause, recovery, ownership transfer

### Stress Testing: ✅ 19/19 STRESS TESTS PASSING
- **High-Volume Transactions**: Concurrent user operations
- **Economic Attack Simulations**: Whale manipulation resistance
- **Extreme Values**: Edge cases with maximum amounts
- **Memory Exhaustion**: Large-scale operations validation

---

## Build and Test

```shell
# Install dependencies
pnpm install

# Compile contracts
pnpm build

# Run tests with gas reporting
pnpm test

# Run tests with console logs
pnpm test:logs

# Clean build artifacts
pnpm clean

# Deploy to local network
pnpm deploy:local

# Deploy to testnet (ECM testnet)
pnpm deploy:testnet
```

---

## Deployment

### 1. Compile Contracts
```bash
pnpm build
```

### 2. Deploy All Contracts
```bash
# Deploy PoolManager, LiquidityManager, VestingManager
pnpm deploy:testnet

# Or use deployment script
npx hardhat run ignition/modules/poolManager.ts --network ecm_testnet
```

### 3. Verify Contracts (Optional)
```bash
pnpm verify:testnet
```

### 4. Initial Configuration
```typescript
// Setup VestingManager in PoolManager
await poolManager.setVestingManager(vestingManagerAddress);

// Setup callback in LiquidityManager
await liquidityManager.setCallbackContract(poolManagerAddress);

// Create first pool (see "Quick Start" section above)
```

### 5. Post-Deployment Checklist
- ✅ VestingManager connected to PoolManager
- ✅ LiquidityManager callback configured
- ✅ Uniswap V2 pair deployed and initialized
- ✅ Admin addresses configured (multisig recommended)
- ✅ Emergency pause/recovery mechanisms tested
- ✅ Contract ownership transferred to multisig

---

## Security Considerations

### Critical Patterns
1. **Token Segregation**: User stakes NEVER mixed with liquidity reserves
2. **Explicit Transfers**: LiquidityManager receives tokens explicitly (no sweeps)
3. **Reentrancy Protection**: All state changes before external calls
4. **Safe Math**: Solidity 0.8+ overflow protection enabled
5. **Access Control**: Owner-only admin functions, multisig recommended


