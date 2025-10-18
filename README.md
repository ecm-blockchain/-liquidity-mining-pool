
# ECM Liquidity Mining Pool

## Overview

This repository contains a comprehensive **three-contract architecture** for ECM token sale, staking, reward distribution, and liquidity management:

- **PoolManager** - Core contract for token sales (USDT→ECM), auto-staking, and reward distribution
- **LiquidityManager** - Dedicated Uniswap V2 liquidity operations handler
- **VestingManager** - Linear vesting schedules for reward claims

This system enables users to purchase ECM tokens with USDT, automatically stake them, earn rewards (LINEAR or MONTHLY strategies), and optionally vest rewards over time. The architecture provides enterprise-grade features with mathematical precision and security.

---

## Architecture Overview

### Three-Contract Design

#### 1. PoolManager (Primary Contract)
The main contract handling:
- **Token Sales**: USDT → ECM purchases with Uniswap V2 pricing
- **Auto-Staking**: Single-call `buyAndStake()` for seamless UX
- **Reward Distribution**: Dual strategies (LINEAR & MONTHLY)
- **Early Unstaking**: Configurable principal slashing (default 25%)
- **Analytics**: Comprehensive on-chain metrics for users and admins

#### 2. LiquidityManager (Isolated Contract)
Dedicated liquidity handler:
- Receives explicit token transfers from PoolManager
- Adds/removes liquidity to Uniswap V2
- Isolated architecture limits blast-radius
- Callback mechanism to track liquidity additions

#### 3. VestingManager (Optional Contract)
Linear vesting system:
- Creates vesting schedules for rewards
- Pro-rata token release over configured duration
- Users claim vested tokens over time
- Reduces sell pressure and aligns incentives

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
    180 * 24 * 60 * 60  // 180 days
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
  30 * 24 * 60 * 60 // 30-day stake duration
);

// Alternative: Buy exact ECM amount
await poolManager.connect(user).buyExactECMAndStake(
  poolId,
  ethers.parseEther("5000"), // Exactly 5000 ECM
  ethers.parseUnits("10000", 6), // Max USDT willing to spend
  30 * 24 * 60 * 60
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
    // Core Configuration
    uint32 id;
    bool active;
    IERC20 ecm;
    IERC20 usdt;
    IUniswapV2Pair pair;
    
    // Penalty Settings
    uint16 penaltyBps;           // Default 2500 (25%)
    address penaltyReceiver;     // Treasury for slashed tokens
    
    // Token Allocation
    uint256 allocatedForSale;    // ECM for public sale
    uint256 allocatedForRewards; // ECM for staking rewards
    uint256 sold;                // Total ECM sold
    uint256 collectedUSDT;       // Total USDT collected
    uint256 liquidityReserve;    // ECM reserved for liquidity
    
    // Staking State
    uint256 totalStaked;         // Current total staked
    uint256 accRewardPerShare;   // Accumulated rewards per share (scaled 1e18)
    uint256 lastRewardTime;      // Last reward update timestamp
    uint256 totalRewardsAccrued; // Total rewards accrued (for capping)
    
    // Reward Strategy
    RewardStrategy rewardStrategy; // LINEAR or MONTHLY
    uint256 rewardRatePerSecond;   // For LINEAR
    uint256[] monthlyRewards;      // For MONTHLY
    uint256 monthlyRewardIndex;    // Current month index
    uint256 monthlyRewardStart;    // Month tracking start time
    
    // Vesting
    uint256 vestingDuration;
    bool vestRewardsByDefault;
    
    // Analytics
    uint256 poolCreatedAt;
    uint256 totalPenaltiesCollected;
    uint256 peakTotalStaked;
    uint256 totalUniqueStakers;
    uint256 lifetimeStakeVolume;
    uint256 lifetimeUnstakeVolume;
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

// Set liquidity reserve
function setLiquidityReserve(uint256 poolId, uint256 amount) external onlyOwner

// Activate/deactivate pool
function setPoolActive(uint256 poolId, bool active) external onlyOwner
```

#### Reward Configuration
```solidity
// LINEAR strategy
function setLinearRewardRate(uint256 poolId, uint256 rewardRatePerSecond) external onlyOwner

// MONTHLY strategy
function setMonthlyRewards(uint256 poolId, uint256[] calldata monthlyAmounts) external onlyOwner

// Update staking rules
function setAllowedStakeDurations(uint256 poolId, uint256[] calldata durations) external onlyOwner
function setPenaltyConfig(uint256 poolId, uint16 penaltyBps, address penaltyReceiver) external onlyOwner
function setVestingConfig(uint256 poolId, uint256 vestingDuration, bool vestByDefault) external onlyOwner
```

#### Contract Integration
```solidity
// Set VestingManager
function setVestingManager(address _vestingManager) external onlyOwner

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
```

### User Functions

#### Buying & Staking
```solidity
// Buy with max USDT amount
function buyAndStake(
    uint256 poolId,
    uint256 maxUsdtAmount,
    uint256 selectedStakeDuration
) external nonReentrant whenNotPaused

// Buy exact ECM amount
function buyExactECMAndStake(
    uint256 poolId,
    uint256 exactEcmAmount,
    uint256 maxUsdtAmount,
    uint256 selectedStakeDuration
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
    uint256 usdtPerEcm,    // Price in USDT per ECM
    uint256 reserveECM,
    uint256 reserveUSDT
)

// Estimate costs
function getRequiredUSDTForExactECM(uint256 poolId, uint256 exactEcm) external view returns (uint256)
function estimateECMForUSDT(uint256 poolId, uint256 usdtAmount) external view returns (uint256)
```

#### Analytics
```solidity
// APR calculations
function calculateAPR(uint256 poolId) external view returns (uint256 apr)
function calculateMonthlyAPR(uint256 poolId, uint256 monthsToProject) external view returns (uint256)

// User projections
function calculateExpectedRewards(uint256 poolId, address user, uint256 durationSeconds) external view returns (uint256)
function calculateROI(uint256 poolId, address user, uint256 durationSeconds, uint256 ecmPriceInUsdt) external view returns (uint256)

// Pool metrics
function calculateTVL(uint256 poolId, uint256 ecmPriceInUsdt) external view returns (uint256)
function calculateUtilizationRate(uint256 poolId) external view returns (uint256)
function calculateRewardDepletionTime(uint256 poolId) external view returns (uint256, uint256, bool)

// Comprehensive analytics
function getPoolAnalytics(uint256 poolId, uint256 ecmPriceInUsdt) external view returns (...)
function getUserAnalytics(uint256 poolId, address user) external view returns (...)
function calculateUnstakePenalty(uint256 poolId, address user) external view returns (...)
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


