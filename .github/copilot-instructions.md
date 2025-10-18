# ECMCoin PoolManager - AI Coding Agent Instructions (Plan B)

## Project Overview
Two-contract architecture for ECM token sale, staking, and liquidity management:
- **PoolManager**: Core contract handling token sales (USDT→ECM), staking, reward distribution, and vesting
- **LiquidityManager**: Dedicated Uniswap V2 liquidity handler (receives explicit token transfers)
- **VestingManager** (optional): Handles linear vesting schedules for reward claims

## Core Architecture - Two-Contract Design

### PoolManager (Primary Contract)
**Inheritance**: `Ownable`, `Pausable`, `ReentrancyGuard`
**Token Handling**: OpenZeppelin `SafeERC20` for ECM and USDT (handles non-standard tokens)

**Key Responsibilities**:
- Token sale: USDT → ECM purchases with TWAP/spot pricing
- Auto-staking on purchase via single-call `buyAndStake()`
- Reward distribution using canonical `accRewardPerShare` pattern (scaled 1e18)
- Early unstaking with configurable principal slashing (default 25% = 2500 bps)
- Vesting integration for reward claims
- Explicit token segregation (user stakes vs liquidity reserves vs admin allocations)

**Critical**: PoolManager NEVER sweeps user-staked tokens. Only explicitly marked `liquidityReserve` or admin-allocated balances can be moved.

### LiquidityManager (Separate Contract)
**Inheritance**: `Ownable` (multisig recommended)
**Purpose**: Receives explicit token transfers and adds liquidity to Uniswap V2
**Isolation**: Does NOT access PoolManager internals, limits blast-radius

### Pool Structure (Tight Variable Packing)
```solidity
enum RewardStrategy { LINEAR, MONTHLY }

struct Pool {
    // Slot 1: Addresses (20 bytes each)
    IERC20 ecm;                  // 20 bytes
    IERC20 usdt;                 // 20 bytes
    
    // Slot 2: Addresses
    IUniswapV2Pair uniswapPair;  // 20 bytes
    address penaltyReceiver;     // 20 bytes (treasury/burn for slashed tokens)
    
    // Slot 3: Supply/Accounting
    uint128 allocatedForSale;    // 16 bytes
    uint128 allocatedForRewards; // 16 bytes
    
    // Slot 4: Supply/Accounting continued
    uint128 sold;                // 16 bytes
    uint128 collectedUSDT;       // 16 bytes
    
    // Slot 5: Supply/Accounting continued
    uint128 liquidityReserve;    // 16 bytes (explicitly for liquidity)
    uint128 totalStaked;         // 16 bytes
    
    // Slot 6: Reward Accounting
    uint256 accRewardPerShare;   // 32 bytes (scaled by 1e18)
    
    // Slot 7: Timestamps
    uint64 lastRewardTime;       // 8 bytes
    uint64 vestingDuration;      // 8 bytes
    uint32 minPurchase;          // 4 bytes (500 ECM as uint32 sufficient)
    uint32 minPurchaseMultiple;  // 4 bytes (500 ECM)
    uint16 penaltyBps;           // 2 bytes (max 65535 bps, default 2500 = 25%)
    RewardStrategy strategy;     // 1 byte (LINEAR or MONTHLY)
    bool vestRewardsByDefault;   // 1 byte
    bool active;                 // 1 byte
    
    // Slot 8: Reward rate (for LINEAR) or monthly schedule pointer
    uint256 rewardRatePerSecond; // For LINEAR: rewards per second
    
    // Dynamic arrays (separate storage slots)
    uint256[] allowedStakeDurations; // e.g., [30 days, 90 days, 180 days]
    uint256[] monthlyRewards;        // For MONTHLY: [month1Amount, month2Amount, ...]
}
```

### UserInfo Structure
```solidity
struct UserInfo {
    uint256 bought;       // ECM credited but held in contract
    uint256 staked;       // Currently staked ECM
    uint256 stakeStart;   // Timestamp of stake
    uint256 stakeDuration; // Selected duration
    uint256 rewardDebt;   // For accRewardPerShare calculation
    uint256 pendingRewards; // Unclaimed rewards
}
```

## Critical UX Pattern: Single-Call buyAndStake()

### Function Signature
```solidity
function buyAndStake(
    uint256 poolId, 
    uint256 maxUsdtAmount, 
    uint256 selectedStakeDuration
) external nonReentrant whenNotPaused
```

### Execution Flow (MUST follow this exact order)
1. **Validate**: Pool active, `selectedStakeDuration` in `allowedStakeDurations`
2. **Get Price**: Query Uniswap V2 pair reserves directly via `getReserves()`
3. **Calculate ECM**: Use `getAmountOut` formula to derive ECM for `maxUsdtAmount`
4. **Floor to 500**: `ecmToAllocate = (ecmRaw / 500) * 500`, revert if < 500
5. **Inverse Calculate USDT**: Use `getAmountIn` to compute exact `usdtRequired` for `ecmToAllocate`
6. **Slippage Check**: Require `usdtRequired <= maxUsdtAmount`
7. **Pull USDT**: `transferFrom(msg.sender, address(this), usdtRequired)`
8. **Update Accounting**:
   - `pool.sold += ecmToAllocate`
   - `pool.collectedUSDT += usdtRequired`
   - `user.bought += ecmToAllocate`
9. **Auto-Stake**:
   - Move `bought` → `staked`
   - `pool.totalStaked += ecmToAllocate`
   - `user.rewardDebt = user.staked * accRewardPerShare / 1e18`
   - `user.stakeStart = block.timestamp`
   - `user.stakeDuration = selectedStakeDuration`
10. **Refund**: Transfer `leftover = maxUsdtAmount - usdtRequired` to buyer if > 0
11. **Emit**: `BoughtAndStaked(user, poolId, ecmToAllocate, usdtRequired, selectedStakeDuration)`

## Reward Distribution - accRewardPerShare Pattern

### Update Pool Rewards (Call before ANY pool interaction)
```solidity
function _updatePoolRewards(uint256 poolId) internal {
    Pool storage pool = pools[poolId];
    if (block.timestamp <= pool.lastRewardTime) return;
    if (pool.totalStaked == 0) {
        pool.lastRewardTime = block.timestamp;
        return;
    }
    
    uint256 delta = block.timestamp - pool.lastRewardTime;
    uint256 rewardAccrued;
    
    if (pool.strategy == RewardStrategy.LINEAR) {
        // LINEAR: constant rate per second
        rewardAccrued = delta * pool.rewardRatePerSecond;
    } else {
        // MONTHLY: calculate based on elapsed months
        rewardAccrued = _calculateMonthlyRewards(pool, delta);
    }
    
    pool.accRewardPerShare += (rewardAccrued * 1e18) / pool.totalStaked;
    pool.lastRewardTime = block.timestamp;
}

function _calculateMonthlyRewards(Pool storage pool, uint256 delta) internal view returns (uint256) {
    // Calculate which month(s) have passed and sum rewards
    // Example: if monthlyRewards = [1000e18, 2000e18, 3000e18]
    // and we're in month 2, distribute proportionally from that month's allocation
    uint256 monthsPassed = delta / 30 days;
    uint256 totalRewards = 0;
    
    for (uint256 i = 0; i < monthsPassed && i < pool.monthlyRewards.length; i++) {
        totalRewards += pool.monthlyRewards[i];
    }
    
    return totalRewards;
}
```

### Pending Reward Calculation
```solidity
uint256 pending = (user.staked * pool.accRewardPerShare / 1e18) - user.rewardDebt;
```

## Early Unstaking with Principal Slashing

### Unstake Logic
```solidity
function unstake(uint256 poolId) external nonReentrant {
    _updatePoolRewards(poolId);
    Pool storage pool = pools[poolId];
    UserInfo storage user = userInfo[msg.sender][poolId];
    
    bool isEarly = block.timestamp < user.stakeStart + user.stakeDuration;
    uint256 slashed = 0;
    uint256 remaining = user.staked;
    
    if (isEarly) {
        // Slash 25% of principal (default penaltyBps = 2500)
        slashed = (user.staked * pool.penaltyBps) / 10000;
        remaining = user.staked - slashed;
        
        // Transfer slashed to penalty receiver
        IERC20(pool.ecm).safeTransfer(pool.penaltyReceiver, slashed);
        emit EarlyUnstaked(msg.sender, poolId, remaining, slashed);
    }
    
    // Calculate rewards (NOT slashed)
    uint256 pending = (user.staked * pool.accRewardPerShare / 1e18) - user.rewardDebt;
    
    // Update accounting
    pool.totalStaked -= user.staked;
    user.staked = 0;
    user.rewardDebt = 0;
    
    // Transfer principal (minus slash if early)
    IERC20(pool.ecm).safeTransfer(msg.sender, remaining);
    
    // Handle rewards separately (see claimRewards)
    if (pending > 0) {
        _claimOrVestRewards(msg.sender, poolId, pending);
    }
}
```

**CRITICAL**: Rewards are NEVER slashed, only principal is slashed on early unstake.

## VestingManager Integration

### VestingManager Contract
```solidity
contract VestingManager is Ownable {
    using SafeERC20 for IERC20;
    
    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 startTime;
        uint256 duration;
        uint256 claimed;
    }
    
    mapping(uint256 => VestingSchedule) public vestingSchedules;
    mapping(address => uint256[]) public userVestingIds;
    uint256 public nextVestingId;
    
    IERC20 public token;
    
    event VestingCreated(uint256 indexed vestingId, address indexed beneficiary, uint256 amount, uint256 duration);
    event VestingClaimed(uint256 indexed vestingId, address indexed beneficiary, uint256 amount);
}
```

### Create Vesting from PoolManager
```solidity
function _claimOrVestRewards(address user, uint256 poolId, uint256 amount) internal {
    Pool storage pool = pools[poolId];
    
    // Determine if vesting is required
    bool shouldVest = pool.vestRewardsByDefault || _userRequestedVesting[user][poolId];
    
    if (shouldVest && address(vestingManager) != address(0) && pool.vestingDuration > 0) {
        // Transfer rewards to VestingManager
        IERC20(pool.ecm).safeTransfer(address(vestingManager), amount);
        
        // Create vesting schedule
        uint256 vestingId = vestingManager.createVesting(
            user,
            amount,
            block.timestamp,
            pool.vestingDuration
        );
        
        emit RewardsVested(user, poolId, amount, vestingId);
    } else {
        // Direct transfer
        IERC20(pool.ecm).safeTransfer(user, amount);
        emit RewardsClaimed(user, poolId, amount);
    }
}
```

### VestingManager Functions
```solidity
// Called by PoolManager (only authorized contract can create)
function createVesting(
    address beneficiary,
    uint256 amount,
    uint256 startTime,
    uint256 duration
) external onlyAuthorized returns (uint256 vestingId) {
    vestingId = nextVestingId++;
    
    vestingSchedules[vestingId] = VestingSchedule({
        beneficiary: beneficiary,
        totalAmount: amount,
        startTime: startTime,
        duration: duration,
        claimed: 0
    });
    
    userVestingIds[beneficiary].push(vestingId);
    
    emit VestingCreated(vestingId, beneficiary, amount, duration);
    return vestingId;
}

// Called by users to claim vested tokens
function claimVested(uint256 vestingId) external nonReentrant {
    VestingSchedule storage schedule = vestingSchedules[vestingId];
    require(schedule.beneficiary == msg.sender, "Not beneficiary");
    
    uint256 vested = _calculateVested(schedule);
    uint256 claimable = vested - schedule.claimed;
    require(claimable > 0, "Nothing to claim");
    
    schedule.claimed += claimable;
    token.safeTransfer(msg.sender, claimable);
    
    emit VestingClaimed(vestingId, msg.sender, claimable);
}

// Linear vesting calculation
function _calculateVested(VestingSchedule memory schedule) internal view returns (uint256) {
    if (block.timestamp < schedule.startTime) return 0;
    if (block.timestamp >= schedule.startTime + schedule.duration) return schedule.totalAmount;
    
    uint256 elapsed = block.timestamp - schedule.startTime;
    return (schedule.totalAmount * elapsed) / schedule.duration;
}
```

## Uniswap V2 Price Oracle - Direct Reserve Pricing

### Get Current Price from Reserves
```solidity
function getPrice(uint256 poolId) public view returns (uint256 ecmPerUsdt) {
    Pool storage pool = pools[poolId];
    IUniswapV2Pair pair = IUniswapV2Pair(pool.uniswapPair);
    
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    
    // Determine which reserve is ECM and which is USDT
    address token0 = pair.token0();
    (uint256 reserveECM, uint256 reserveUSDT) = token0 == address(pool.ecm) 
        ? (uint256(reserve0), uint256(reserve1))
        : (uint256(reserve1), uint256(reserve0));
    
    // Price = reserveUSDT / reserveECM (scaled appropriately)
    return (reserveUSDT * 1e18) / reserveECM;
}
```

### Calculate ECM Amount Out (for buying)
```solidity
function getECMAmountOut(uint256 poolId, uint256 usdtAmountIn) public view returns (uint256) {
    Pool storage pool = pools[poolId];
    IUniswapV2Pair pair = IUniswapV2Pair(pool.uniswapPair);
    
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    address token0 = pair.token0();
    
    (uint256 reserveIn, uint256 reserveOut) = token0 == address(pool.usdt)
        ? (uint256(reserve0), uint256(reserve1))
        : (uint256(reserve1), uint256(reserve0));
    
    // Uniswap V2 formula with 0.3% fee
    uint256 amountInWithFee = usdtAmountIn * 997;
    uint256 numerator = amountInWithFee * reserveOut;
    uint256 denominator = (reserveIn * 1000) + amountInWithFee;
    
    return numerator / denominator;
}
```

### Calculate USDT Amount In (inverse - for exact ECM)
```solidity
function getUSDTAmountIn(uint256 poolId, uint256 ecmAmountOut) public view returns (uint256) {
    Pool storage pool = pools[poolId];
    IUniswapV2Pair pair = IUniswapV2Pair(pool.uniswapPair);
    
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    address token0 = pair.token0();
    
    (uint256 reserveIn, uint256 reserveOut) = token0 == address(pool.usdt)
        ? (uint256(reserve0), uint256(reserve1))
        : (uint256(reserve1), uint256(reserve0));
    
    // Inverse Uniswap V2 formula
    uint256 numerator = reserveIn * ecmAmountOut * 1000;
    uint256 denominator = (reserveOut - ecmAmountOut) * 997;
    
    return (numerator / denominator) + 1; // +1 for rounding
}
```

## Token Segregation & Liquidity Transfer

### Admin Transfer to LiquidityManager
```solidity
function transferToLiquidityManager(
    uint256 ecmAmount,
    uint256 usdtAmount,
    address liquidityManager
) external onlyOwner {
    // Verify amounts are from liquidityReserve or admin allocations
    // NEVER touch user-staked tokens
    
    IERC20(ecm).safeTransfer(liquidityManager, ecmAmount);
    IERC20(usdt).safeTransfer(liquidityManager, usdtAmount);
    
    emit LiquidityTransferred(liquidityManager, ecmAmount, usdtAmount);
}
```

### LiquidityManager.addLiquidity()
```solidity
function addLiquidity(
    uint256 ecmAmount,
    uint256 usdtAmount,
    uint256 minEcm,
    uint256 minUsdt,
    address to,
    uint256 deadline
) external onlyOwner {
    IERC20(ecm).approve(address(uniswapRouter), ecmAmount);
    IERC20(usdt).approve(address(uniswapRouter), usdtAmount);
    
    uniswapRouter.addLiquidity(
        address(ecm), address(usdt),
        ecmAmount, usdtAmount,
        minEcm, minUsdt,
        to, deadline
    );
    
    emit LiquidityAdded(ecmAmount, usdtAmount, to);
}
```

## Complete Admin API

### Pool Creation & Allocation
```solidity
// Create new pool with ECM/USDT pair
function createPool(
    address ecmToken,
    address usdtToken,
    address uniswapPair,
    address penaltyReceiver,
    RewardStrategy strategy,
    uint256[] calldata allowedStakeDurations,
    uint256 vestingDuration,
    bool vestRewardsByDefault
) external onlyOwner returns (uint256 poolId);

// Allocate ECM tokens for sale (pulled from admin)
function allocateForSale(uint256 poolId, uint256 amount) external onlyOwner {
    Pool storage pool = pools[poolId];
    IERC20(pool.ecm).safeTransferFrom(msg.sender, address(this), amount);
    pool.allocatedForSale += amount;
    emit AllocatedForSale(poolId, amount);
}

// Allocate ECM tokens for rewards (pulled from admin)
function allocateForRewards(uint256 poolId, uint256 amount) external onlyOwner {
    Pool storage pool = pools[poolId];
    IERC20(pool.ecm).safeTransferFrom(msg.sender, address(this), amount);
    pool.allocatedForRewards += amount;
    emit AllocatedForRewards(poolId, amount);
}

// Set liquidity reserve (designate portion for liquidity)
function setLiquidityReserve(uint256 poolId, uint256 amount) external onlyOwner {
    Pool storage pool = pools[poolId];
    require(amount <= pool.allocatedForSale - pool.sold, "Insufficient available");
    pool.liquidityReserve = amount;
    emit LiquidityReserveSet(poolId, amount);
}
```

### Reward Strategy Configuration
```solidity
// Configure LINEAR reward strategy
function setLinearRewardRate(uint256 poolId, uint256 rewardRatePerSecond) external onlyOwner {
    Pool storage pool = pools[poolId];
    require(pool.strategy == RewardStrategy.LINEAR, "Not LINEAR strategy");
    
    _updatePoolRewards(poolId); // Update before changing rate
    pool.rewardRatePerSecond = rewardRatePerSecond;
    
    emit LinearRewardRateSet(poolId, rewardRatePerSecond);
}

// Configure MONTHLY reward strategy
function setMonthlyRewards(uint256 poolId, uint256[] calldata monthlyAmounts) external onlyOwner {
    Pool storage pool = pools[poolId];
    require(pool.strategy == RewardStrategy.MONTHLY, "Not MONTHLY strategy");
    
    _updatePoolRewards(poolId); // Update before changing schedule
    
    // Verify total rewards don't exceed allocated
    uint256 totalMonthly = 0;
    for (uint256 i = 0; i < monthlyAmounts.length; i++) {
        totalMonthly += monthlyAmounts[i];
    }
    require(totalMonthly <= pool.allocatedForRewards, "Exceeds allocated rewards");
    
    pool.monthlyRewards = monthlyAmounts;
    
    emit MonthlyRewardsSet(poolId, monthlyAmounts);
}
```

### Pool Configuration
```solidity
// Update allowed stake durations
function setAllowedStakeDurations(uint256 poolId, uint256[] calldata durations) external onlyOwner {
    pools[poolId].allowedStakeDurations = durations;
    emit AllowedStakeDurationsUpdated(poolId, durations);
}

// Update penalty configuration
function setPenaltyConfig(uint256 poolId, uint256 penaltyBps, address penaltyReceiver) external onlyOwner {
    require(penaltyBps <= 10000, "Invalid bps");
    Pool storage pool = pools[poolId];
    pool.penaltyBps = uint16(penaltyBps);
    pool.penaltyReceiver = penaltyReceiver;
    emit PenaltyConfigUpdated(poolId, penaltyBps, penaltyReceiver);
}

// Update vesting configuration
function setVestingConfig(uint256 poolId, uint256 vestingDuration, bool vestByDefault) external onlyOwner {
    Pool storage pool = pools[poolId];
    pool.vestingDuration = uint64(vestingDuration);
    pool.vestRewardsByDefault = vestByDefault;
    emit VestingConfigUpdated(poolId, vestingDuration, vestByDefault);
}

// Activate/deactivate pool
function setPoolActive(uint256 poolId, bool active) external onlyOwner {
    pools[poolId].active = active;
    emit PoolActiveStatusChanged(poolId, active);
}

// Set VestingManager contract
function setVestingManager(address _vestingManager) external onlyOwner {
    vestingManager = IVestingManager(_vestingManager);
    emit VestingManagerSet(_vestingManager);
}
```

### Emergency & Governance
```solidity
// Pause all operations (inherited from Pausable)
function pause() external onlyOwner {
    _pause();
}

function unpause() external onlyOwner {
    _unpause();
}

// Emergency withdraw mistakenly sent tokens (NOT user stakes)
function emergencyRecoverTokens(address token, uint256 amount) external onlyOwner {
    require(token != address(0), "Invalid token");
    // Add checks to prevent withdrawing user-staked tokens
    IERC20(token).safeTransfer(owner(), amount);
    emit EmergencyTokenRecovery(token, amount);
}
```

## Development Workflows

### Testing Priorities
1. **Pricing & Rounding**: TWAP vs spot, 500-ECM multiples, floor < 500 rejection
2. **buyAndStake**: Single-call flow, refunds, slippage protection
3. **Reward Accrual**: LINEAR strategy, time progression, `accRewardPerShare` math
4. **Early Unstake**: 25% principal slash, rewards intact, penalty receiver
5. **Liquidity Transfer**: Segregation enforcement, LiquidityManager isolation
6. **USDT Edge Cases**: Non-standard transfer behavior
7. **Reentrancy**: All state changes before external calls

### Build & Deploy Commands
```bash
# Build contracts
pnpm build

# Run comprehensive tests with gas reporting
pnpm test

# Deploy PoolManager, LiquidityManager, VestingManager
pnpm deploy:network <network-name>

# Verify all contracts
pnpm verify:network <network-name>
```

## Security Patterns

### Checks-Effects-Interactions
Always update state before external transfers:
```solidity
// ✅ CORRECT
user.staked = 0;
pool.totalStaked -= amount;
IERC20(token).safeTransfer(user, amount);

// ❌ WRONG
IERC20(token).safeTransfer(user, amount);
user.staked = 0;
```

### Reentrancy Protection
All user-facing functions use `nonReentrant` modifier.

### Integer Overflow Protection
Solidity 0.8+ checked math enabled. Use `>=0.8.17` for best practices.

### USDT Non-Standard Behavior
Use `SafeERC20.safeTransfer` and `safeTransferFrom` for all ERC20 operations.

## Critical Constants

```solidity
uint256 constant MIN_PURCHASE = 500 ether;  // 500 ECM minimum
uint256 constant PURCHASE_MULTIPLE = 500 ether;  // Must be multiple of 500
uint256 constant DEFAULT_PENALTY_BPS = 2500;  // 25% slash
uint256 constant ACC_REWARD_PRECISION = 1e18;  // accRewardPerShare scaling
uint256 constant MONTH_DURATION = 30 days;  // For MONTHLY strategy
```

## Event Model
```solidity
event PoolCreated(uint256 indexed poolId, address ecm, address usdt);
event AllocatedForSale(uint256 indexed poolId, uint256 amount);
event AllocatedForRewards(uint256 indexed poolId, uint256 amount);
event BoughtAndStaked(address indexed user, uint256 indexed poolId, uint256 ecm, uint256 usdt, uint256 duration);
event Unstaked(address indexed user, uint256 indexed poolId, uint256 amount);
event EarlyUnstaked(address indexed user, uint256 indexed poolId, uint256 amount, uint256 slashed);
event RewardsClaimed(address indexed user, uint256 indexed poolId, uint256 amount);
event RewardsVested(address indexed user, uint256 indexed poolId, uint256 amount);
event LiquidityTransferred(address indexed liquidityManager, uint256 ecm, uint256 usdt);
event LiquidityAdded(uint256 ecm, uint256 usdt, address indexed to);
```

## Network Configuration
- **Local**: Hardhat network (chainId 1337)
- **Testnet**: ECM testnet (chainId 1124, RPC: https://rpc.testnet.ecmscan.io)
- **Public**: Sepolia (with Etherscan verification)

## File Structure (Plan B)
```
contracts/
  PoolManager.sol          // Main sale/stake/reward contract
  LiquidityManager.sol     // Uniswap V2 liquidity handler
  VestingManager.sol       // Optional vesting contract
  interfaces/
    IUniswapV2Router02.sol
    IUniswapV2Pair.sol
  test/
    MockERC20.sol
    MockUSDT.sol           // Non-standard ERC20 for testing
test/
  PoolManager.spec.ts      // Comprehensive tests
  LiquidityManager.spec.ts
  integration.spec.ts      // Full flow tests
ignition/
  modules/
    poolManager.ts         // Deployment module
```

## Common Gotchas
- **500 ECM Enforcement**: Floor ALL calculated ECM amounts, reject if < 500
- **Principal Slashing**: Only principal slashed (25%), NEVER rewards
- **Token Segregation**: User stakes are untouchable by admin sweeps
- **Refund Logic**: Always refund excess USDT in same transaction
- **Reward Debt**: Update after EVERY staking/unstaking operation
- **accRewardPerShare Scaling**: Always use 1e18 precision to prevent rounding errors
- **USDT Approval**: Some USDT implementations require approval(0) before new approval
- **Reserve Reading**: Always check token0 vs token1 ordering in Uniswap pair
- **Monthly Rewards**: Handle edge cases when month boundaries overlap with claim times

## Migration from Current StakingPool
This Plan B architecture is a COMPLETE REDESIGN. Do not attempt to retrofit the existing `StakingPool.sol`:
- Current contract: Generic multi-pool staking with arbitrary tokens
- Plan B: Specialized sale+stake system with USDT→ECM conversion, TWAP pricing, and liquidity separation
- Start with clean contracts following this specification
- Reuse patterns: `accRewardPerShare`, `SafeERC20`, `ReentrancyGuard`
- New patterns: TWAP oracle, 500-ECM multiples, slippage protection, token segregation