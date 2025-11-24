// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Import Uniswap V2 interfaces
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IReferralVoucher} from "./interfaces/IReferralVoucher.sol";
import {IReferralModule} from "./interfaces/IReferralModule.sol";

interface IVestingManager {
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 start,
        uint256 duration,
        address token,
        uint256 poolId
    ) external returns (uint256 vestingId);
}

/// @title PoolManager - ECM Token Sale, Staking, and Reward Distribution
/// @notice Handles USDT→ECM purchases with auto-staking, reward distribution, and early unstaking penalties
/// @dev Two-contract architecture: PoolManager (core) + LiquidityManager (separate liquidity operations)
contract PoolManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // CONSTANTS
    // ============================================

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_PURCHASE_ECM = 500 ether; // 500 ECM minimum
    uint256 public constant DEFAULT_PENALTY_BPS = 2500; // 25% slash
    uint256 public constant MAX_BPS = 10000;

    uint256 public constant WEEK_SECONDS = 7 * 24 * 3600; // 7 days
    uint256 public constant WEEKS_IN_YEAR = (365 days) / WEEK_SECONDS; // = 52

    // ============================================
    // ENUMS & STRUCTS
    // ============================================

    /// @notice Reward distribution strategy for a pool
    /// @dev LINEAR: Constant rate per second | MONTHLY: Fixed amounts per month
    enum RewardStrategy {
        LINEAR,
        MONTHLY,
        WEEKLY
    }

    /// @notice Pool configuration and state tracking
    /// @dev Main data structure for managing token sale, staking, and rewards
    struct Pool {
        // Core Pool Identification
        uint32 id; // Unique pool identifier
        bool active; // Whether pool accepts new purchases/stakes
        // Token Configuration
        IERC20 ecm; // ECM token contract address
        IERC20 usdt; // USDT token contract address (payment token)
        IUniswapV2Pair pair; // Uniswap V2 ECM/USDT pair for pricing
        // Penalty Configuration
        uint16 penaltyBps; // Early unstake penalty in basis points (2500 = 25%)
        address penaltyReceiver; // Address receiving slashed tokens (treasury/burn)
        // Token Allocation & Sale Tracking
        /// @notice Total ECM allocated for public sale (must be transferred by admin)
        uint256 allocatedForSale;
        /// @notice Total ECM allocated for staking rewards (must be transferred by admin)
        uint256 allocatedForRewards;
        /// @notice Total ECM sold to users (all are also staked)
        uint256 sold;
        uint256 collectedUSDT; // Total USDT collected from sales
        // Staking State
        /// @notice Total ECM currently staked by all users (equal to 'sold')
        uint256 totalStaked;
        // Reward Distribution (accRewardPerShare Pattern)
        uint256 accRewardPerShare; // Accumulated rewards per share, scaled by PRECISION (1e18)
        // Formula: sum(rewardRate * timeDelta / totalStaked)
        // Used to calculate: userReward = (userStake * accRewardPerShare / PRECISION) - userRewardDebt
        uint256 lastRewardTime; // Last timestamp when accRewardPerShare was updated
        // Reward Strategy Configuration
        RewardStrategy rewardStrategy; // LINEAR or MONTHLY reward distribution
        uint256 rewardRatePerSecond; // For LINEAR: rewards per second (e.g., 1e18 = 1 ECM/sec)
        // Staking Duration Rules
        uint256[] allowedStakeDurations; // Allowed lock periods (e.g., [30 days, 90 days, 180 days])
        uint256 maxDuration; // Maximum allowed staking duration
        // Vesting Configuration
        uint256 vestingDuration; // Linear vesting period for rewards (e.g., 180 days)
        bool vestRewardsByDefault; // If true, rewards auto-vest; if false, user chooses
        // Monthly Reward Strategy Data
        uint256[] monthlyRewards; // For MONTHLY: rewards per month [month1, month2, ...]
        uint256 monthlyRewardIndex; // Current month index in monthlyRewards array
        uint256 monthlyRewardStart; // Timestamp when monthly rewards started
        // Weekly Reward Strategy Data
        uint256[] weeklyRewards; // For WEEKLY: rewards per week [week1, week2, ...]
        uint256 weeklyRewardIndex; // Current week index in weeklyRewards array
        uint256 weeklyRewardStart; // Timestamp when weekly rewards started
        // Liquidity Tracking (Two-Level System)
        uint256 liquidityPoolOwedECM; // Net ECM moved to LiquidityManager (in - out)
        uint256 ecmMovedToLiquidity; // Total ECM transferred to LiquidityManager contract
        uint256 usdtMovedToLiquidity; // Total USDT transferred to LiquidityManager contract
        uint256 ecmAddedToUniswap; // ECM actually added to Uniswap pool (via callback)
        uint256 usdtAddedToUniswap; // USDT actually added to Uniswap pool (via callback)
        // Vesting & Rewards Tracking
        uint256 ecmVested; // Total ECM sent to VestingManager for linear vesting
        uint256 rewardsPaid; // Total rewards paid out (immediate + vested)
        uint256 totalRewardsAccrued; // Total rewards accrued via accRewardPerShare (for capping)
        // Historical & Analytics Data (for off-chain calculations)
        uint256 poolCreatedAt; // Timestamp when pool was created
        uint256 totalPenaltiesCollected; // Total ECM collected from early unstake penalties
        uint256 peakTotalStaked; // Highest totalStaked value ever reached (for analytics)
        uint256 totalUniqueStakers; // Count of unique addresses that have staked
        uint256 lifetimeStakeVolume; // Cumulative ECM staked (including re-stakes)
        uint256 lifetimeUnstakeVolume; // Cumulative ECM unstaked
    }

    /// @notice Per-user staking and reward information
    /// @dev Tracks user's position in a specific pool
    struct UserInfo {
        uint256 bought; // Total ECM purchased by user (historical, currently unused)
        uint256 staked; // Currently staked ECM amount
        uint256 stakeStart; // Timestamp when current stake began
        uint256 stakeDuration; // Selected lock duration (from allowedStakeDurations)
        // Reward Calculation (accRewardPerShare Pattern)
        uint256 rewardDebt; // Reward debt for accRewardPerShare calculation
        // Formula: rewardDebt = staked * accRewardPerShare / PRECISION
        // Purpose: Tracks rewards already accounted for
        // Pending rewards = (staked * accRewardPerShare / PRECISION) - rewardDebt
        uint256 pendingRewards; // Accumulated unclaimed rewards from previous stakes
        // Historical & Analytics Data
        bool hasStaked; // True if user has ever staked in this pool (for unique staker count)
        uint256 totalStaked; // Lifetime total ECM staked by user
        uint256 totalUnstaked; // Lifetime total ECM unstaked by user
        uint256 totalRewardsClaimed; // Lifetime total rewards claimed by user
        uint256 totalPenaltiesPaid; // Total penalties paid from early unstakes
        uint256 firstStakeTimestamp; // Timestamp of user's first stake in pool
        uint256 lastActionTimestamp; // Timestamp of user's last action (stake/unstake/claim)
    }

    /// @notice Parameters for creating a new pool
    /// @dev Used in createPool() to initialize pool configuration
    struct PoolCreateParams {
        address ecm; // ECM token contract address
        address usdt; // USDT token contract address
        address pair; // Uniswap V2 ECM/USDT pair for price oracle
        address penaltyReceiver; // Address to receive slashed tokens from early unstakes
        RewardStrategy rewardStrategy; // LINEAR or MONTHLY reward distribution
        uint256[] allowedStakeDurations; // Allowed lock periods (e.g., [30d, 90d, 180d])
        uint256 maxDuration; // Maximum allowed staking duration
        uint256 vestingDuration; // Linear vesting duration for rewards (0 = no vesting)
        bool vestRewardsByDefault; // Auto-vest rewards vs user choice
        uint16 penaltyBps; // Early unstake penalty in bps (0 = use DEFAULT_PENALTY_BPS)
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice All pools indexed by poolId
    /// @dev poolId is auto-incremented starting from 0
    mapping(uint256 poolId => Pool pool) public pools;

    /// @notice User staking information per pool
    /// @dev userInfo[userAddress][poolId] => UserInfo
    mapping(uint256 poolId => mapping(address user => UserInfo info)) public userInfo;

    /// @notice Total number of pools created
    /// @dev Used as next poolId when creating new pool
    uint256 public poolCount;

    /// @notice VestingManager contract for linear token vesting
    /// @dev Optional: if not set, rewards paid immediately
    IVestingManager public vestingManager;

    /// @notice Uniswap V2 Router address
    /// @dev Set via constructor - can be mainnet router or mock for testing
    IUniswapV2Router02 public immutable UNISWAP_ROUTER;

    /// @notice Authorized LiquidityManager contracts that can report liquidity additions
    /// @dev Used for callback authorization in recordLiquidityAdded()
    mapping(address manager => bool authorized) public authorizedLiquidityManagers;

    /// @notice ReferralVoucher contract for voucher verification
    IReferralVoucher public referralVoucher;

    /// @notice ReferralModule contract for referral tracking and commissions
    IReferralModule public referralModule;

    // ============================================
    // EVENTS
    // ============================================

    event PoolCreated(
        uint256 indexed poolId,
        address indexed ecm,
        address indexed usdt,
        address pair,
        RewardStrategy poolType
    );
    event WeeklyRewardsSet(uint256 indexed poolId, uint256[] weeklyAmounts);
    event ECMAllocatedForSale(uint256 indexed poolId, uint256 amount);
    event ECMAllocatedForRewards(uint256 indexed poolId, uint256 amount);
    event BoughtAndStaked(
        uint256 indexed poolId,
        address indexed user,
        uint256 ecmAmount,
        uint256 usdtPaid,
        uint256 stakeDuration,
        address referrer,
        bytes32 codeHash
    );
    event ECMStaked(
        uint256 indexed poolId,
        address indexed user,
        uint256 ecmAmount,
        uint256 stakeDuration
    );
    event Unstaked(
        uint256 indexed poolId,
        address indexed user,
        uint256 principalReturned,
        uint256 rewardsPaid
    );
    event EarlyUnstaked(
        uint256 indexed poolId,
        address indexed user,
        uint256 principalReturned,
        uint256 slashed,
        uint256 rewardsPaid
    );
    event RewardsClaimed(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        bool vested
    );
    event LiquidityTransferToManager(
        uint256 indexed poolId,
        address liquidityManager,
        uint256 ecmAmount,
        uint256 usdtAmount
    );
    event LinearRewardRateSet(
        uint256 indexed poolId,
        uint256 rewardRatePerSecond
    );
    event MonthlyRewardsSet(uint256 indexed poolId, uint256[] monthlyAmounts);
    event PenaltyConfigUpdated(
        uint256 indexed poolId,
        uint256 penaltyBps,
        address penaltyReceiver
    );
    event VestingConfigUpdated(
        uint256 indexed poolId,
        uint256 vestingDuration,
        bool vestByDefault
    );
    event RewardsVested(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        uint256 vestingId,
        uint256 duration
    );
    event PoolActiveStatusChanged(uint256 indexed poolId, bool active);
    event VestingManagerSet(address vestingManager);
    event LiquidityReserveSet(uint256 indexed poolId, uint256 amount);
    event AllowedStakeDurationsUpdated(
        uint256 indexed poolId,
        uint256[] durations
    );
    event LiquidityAddedToUniswap(
        uint256 indexed poolId,
        uint256 ecmAmount,
        uint256 usdtAmount
    );
    event LiquidityManagerAuthorized(address indexed manager);
    event LiquidityManagerDeauthorized(address indexed manager);
    event OwedLiquidityRefilled(uint256 indexed poolId, uint256 ecmAmount);
    event ReferralVoucherSet(address indexed referralVoucher);
    event ReferralModuleSet(address indexed referralModule);

    // ============================================
    // ERRORS
    // ============================================

    error PoolNotActive();
    error InvalidAddress();
    error InvalidStakeDuration();
    error InsufficientPoolECM();
    error SlippageExceeded();
    error MinPurchaseNotMet();
    error PoolDoesNotExist();
    error NotStaked();
    error InvalidRewards();
    error InvalidPenaltyBps();
    error InvalidAmount();
    error InvalidStrategy();
    error EmptyWeeklyRewards();
    error UnsustainableRewardRate();
    error ExceedsAllocatedRewards();
    error InsufficientLiquidityReserve();
    error InsufficientLiquidity();
    error CannotWithdrawStakedTokens();
    error ExceedsAllocation();
    error InvalidDuration();
    error NotAuthorizedVestingManager();
    error NotAuthorizedLiquidityManager();
    error InvalidRewardRate();
    error VestingFailed();
    error InsufficientECMForLiquidityTransfer();
    error InsufficientRewardsForRate();

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initializes the PoolManager contract
    /// @param _uniswapRouter Address of Uniswap V2 Router (mainnet or mock)
    /// @dev Pass mainnet router (0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) for production
    ///      or mock router address for testing
    constructor(address _uniswapRouter) Ownable(msg.sender) {
        if (_uniswapRouter == address(0)) revert InvalidAddress();
        UNISWAP_ROUTER = IUniswapV2Router02(_uniswapRouter);
    }

    // ============================================
    // ADMIN FUNCTIONS - POOL MANAGEMENT
    // ============================================

    /// @notice Creates a new pool for ECM token sale and staking
    /// @param params Pool creation parameters
    /// @return poolId The ID of the newly created pool
    function createPool(
        PoolCreateParams calldata params
    ) external onlyOwner returns (uint256 poolId) {
        if (
            params.ecm == address(0) ||
            params.usdt == address(0) ||
            params.pair == address(0)
        ) revert InvalidAddress();
        if (params.penaltyReceiver == address(0)) revert InvalidAddress();
        if (params.penaltyBps > MAX_BPS) revert InvalidPenaltyBps();
        if (params.allowedStakeDurations.length == 0) revert InvalidDuration();
        if (params.maxDuration == 0) revert InvalidDuration();
        uint256 durationsLength = params.allowedStakeDurations.length;
        for (uint256 i = 0; i < durationsLength; ++i) {
            uint256 d = params.allowedStakeDurations[i];
            if (d > params.maxDuration) revert InvalidDuration();
        }

        poolId = poolCount;
        ++poolCount;

        Pool storage pool = pools[poolId];
        pool.id = uint32(poolId);
        pool.active = true;
        pool.ecm = IERC20(params.ecm);
        pool.usdt = IERC20(params.usdt);
        pool.pair = IUniswapV2Pair(params.pair);
        pool.penaltyBps = params.penaltyBps > 0
            ? params.penaltyBps
            : uint16(DEFAULT_PENALTY_BPS);
        pool.penaltyReceiver = params.penaltyReceiver;
        pool.rewardStrategy = params.rewardStrategy;
        pool.allowedStakeDurations = params.allowedStakeDurations;
        pool.maxDuration = params.maxDuration;
        pool.vestingDuration = params.vestingDuration;
        pool.vestRewardsByDefault = params.vestRewardsByDefault;
        pool.lastRewardTime = block.timestamp;
        pool.poolCreatedAt = block.timestamp; // Initialize creation timestamp

        emit PoolCreated(
            poolId,
            params.ecm,
            params.usdt,
            params.pair,
            params.rewardStrategy
        );
    }

    /// @notice Allocates ECM tokens for sale (pulled from admin)
    /// @param poolId The pool ID
    /// @param amount Amount of ECM to allocate
    function allocateForSale(
        uint256 poolId,
        uint256 amount
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (amount == 0) revert InvalidAmount();

        Pool storage pool = pools[poolId];
        pool.ecm.safeTransferFrom(msg.sender, address(this), amount);
        pool.allocatedForSale += amount;

        emit ECMAllocatedForSale(poolId, amount);
    }

    /// @notice Allocates ECM tokens for rewards (pulled from admin)
    /// @param poolId The pool ID
    /// @param amount Amount of ECM to allocate
    function allocateForRewards(
        uint256 poolId,
        uint256 amount
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (amount == 0) revert InvalidAmount();

        Pool storage pool = pools[poolId];
        pool.ecm.safeTransferFrom(msg.sender, address(this), amount);
        pool.allocatedForRewards += amount;

        emit ECMAllocatedForRewards(poolId, amount);
    }

    // Removed setLiquidityReserve; liquidityReserve logic is deprecated

    // ============================================
    // ADMIN FUNCTIONS - REWARD CONFIGURATION
    // ============================================

    /// @notice Configures LINEAR reward strategy rate based on allocated rewards and max duration
    /// @dev Automatically calculates optimal rate from remaining rewards and max duration
    /// @dev Only callable for pools with LINEAR reward strategy
    /// @param poolId The pool ID to configure
    function setLinearRewardRate(uint256 poolId) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        if (pool.rewardStrategy != RewardStrategy.LINEAR)
            revert InvalidStrategy();
        if (pool.maxDuration == 0) revert InvalidDuration();

        _updatePoolRewards(poolId);

        // Validate that reward rate doesn't exceed available rewards
        // This is a sanity check to prevent misconfiguration
        uint256 remainingRewards = pool.allocatedForRewards -
            pool.totalRewardsAccrued;
        if (remainingRewards == 0) revert InsufficientRewardsForRate();

        // Calculate reward rate: raw tokens per second (NOT pre-scaled)
        // This will be scaled later in accRewardPerShare calculation
        uint256 rewardRatePerSecond = remainingRewards / pool.maxDuration;
        if (rewardRatePerSecond == 0) revert InvalidRewardRate();
        pool.rewardRatePerSecond = rewardRatePerSecond;

        emit LinearRewardRateSet(poolId, rewardRatePerSecond);
    }

    /// @notice Configures MONTHLY reward strategy
    /// @param poolId The pool ID
    /// @param monthlyAmounts Array of monthly reward amounts
    function setMonthlyRewards(
        uint256 poolId,
        uint256[] calldata monthlyAmounts
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        if (pool.rewardStrategy != RewardStrategy.MONTHLY)
            revert InvalidStrategy();
        if (monthlyAmounts.length == 0) revert InvalidRewards();

        _updatePoolRewards(poolId);

        // Verify total rewards don't exceed allocated
        uint256 totalMonthly = 0;
        uint256 monthlyLength = monthlyAmounts.length;
        for (uint256 i = 0; i < monthlyLength; ++i) {
            totalMonthly += monthlyAmounts[i];
        }

        if (totalMonthly > pool.allocatedForRewards)
            revert ExceedsAllocatedRewards();

        pool.monthlyRewards = monthlyAmounts;
        pool.monthlyRewardIndex = 0;
        pool.monthlyRewardStart = block.timestamp;

        emit MonthlyRewardsSet(poolId, monthlyAmounts);
    }

    /// @notice Configures WEEKLY reward strategy
    /// @param poolId The pool ID
    /// @param weeklyAmounts Array of weekly reward amounts
    function setWeeklyRewards(
        uint256 poolId,
        uint256[] calldata weeklyAmounts
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (weeklyAmounts.length == 0) revert EmptyWeeklyRewards();
        Pool storage pool = pools[poolId];
        if (pool.rewardStrategy != RewardStrategy.WEEKLY)
            revert InvalidStrategy();
        _updatePoolRewards(poolId); // Update accrued rewards before changes

        // Validate total rewards don't exceed allocated
        uint256 totalWeekly = 0;
        uint256 weeklyLength = weeklyAmounts.length;
        for (uint256 i = 0; i < weeklyLength; ++i) {
            totalWeekly += weeklyAmounts[i];
        }
        if (totalWeekly > pool.allocatedForRewards) revert ExceedsAllocation();

        // Reset and set new weekly rewards
        delete pool.weeklyRewards;
        pool.weeklyRewards = weeklyAmounts;
        pool.weeklyRewardIndex = 0;
        pool.weeklyRewardStart = block.timestamp; // Reset weekly start time
        emit WeeklyRewardsSet(poolId, weeklyAmounts);
    }

    // ============================================
    // ADMIN FUNCTIONS - POOL CONFIGURATION
    // ============================================

    /// @notice Updates allowed stake durations
    /// @param poolId The pool ID
    /// @param durations Array of allowed durations in seconds
    function setAllowedStakeDurations(
        uint256 poolId,
        uint256[] calldata durations
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (durations.length == 0) revert InvalidDuration();

        // Find the maximum duration from the new durations array
        uint256 maxDur = 0;
        uint256 durationsLength = durations.length;
        for (uint256 i = 0; i < durationsLength; ++i) {
            if (durations[i] > maxDur) {
                maxDur = durations[i];
            }
        }
        if (maxDur == 0) revert InvalidDuration();

        Pool storage pool = pools[poolId];
        pool.allowedStakeDurations = durations;
        pool.maxDuration = maxDur;
        
        emit AllowedStakeDurationsUpdated(poolId, durations);
    }

    /// @notice Updates penalty configuration
    /// @param poolId The pool ID
    /// @param penaltyBps Penalty in basis points (2500 = 25%)
    /// @param penaltyReceiver Address to receive slashed tokens
    function setPenaltyConfig(
        uint256 poolId,
        uint16 penaltyBps,
        address penaltyReceiver
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (penaltyBps > MAX_BPS) revert InvalidPenaltyBps();
        if (penaltyReceiver == address(0)) revert InvalidAddress();

        Pool storage pool = pools[poolId];
        pool.penaltyBps = penaltyBps;
        pool.penaltyReceiver = penaltyReceiver;

        emit PenaltyConfigUpdated(poolId, penaltyBps, penaltyReceiver);
    }

    /// @notice Updates vesting configuration
    /// @param poolId The pool ID
    /// @param vestingDuration Duration of vesting in seconds
    /// @param vestByDefault Whether rewards vest by default
    function setVestingConfig(
        uint256 poolId,
        uint256 vestingDuration,
        bool vestByDefault
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        pool.vestingDuration = vestingDuration;
        pool.vestRewardsByDefault = vestByDefault;

        emit VestingConfigUpdated(poolId, vestingDuration, vestByDefault);
    }

    /// @notice Activates or deactivates a pool
    /// @param poolId The pool ID
    /// @param active Whether the pool should be active
    function setPoolActive(uint256 poolId, bool active) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        pools[poolId].active = active;
        emit PoolActiveStatusChanged(poolId, active);
    }

    /// @notice Sets the VestingManager contract address for handling reward vesting
    /// @dev Must be a valid contract address implementing IVestingManager interface
    /// @param _vestingManager Address of the VestingManager contract
    function setVestingManager(address _vestingManager) external onlyOwner {
        if (_vestingManager == address(0)) revert InvalidAddress();
        vestingManager = IVestingManager(_vestingManager);
        emit VestingManagerSet(_vestingManager);
    }

    /// @notice Sets the ReferralVoucher contract address for handling referral systems
    /// @dev Must be a valid contract address implementing IReferralVoucher interface
    /// @param _referralVoucher Address of the ReferralVoucher contract
    function setReferralVoucher(address _referralVoucher) external onlyOwner {
        if (_referralVoucher == address(0)) revert InvalidAddress();
        referralVoucher = IReferralVoucher(_referralVoucher);
        emit ReferralVoucherSet(_referralVoucher);
    }

    /// @notice Sets the ReferralModule contract address
    /// @param _referralModule Address of the ReferralModule contract (can be zero to disable)
    function setReferralModule(address _referralModule) external onlyOwner {
        // Allow zero address to disable referral system
        referralModule = IReferralModule(_referralModule);
        
        // Note: ReferralVoucher.setReferralModule() must be called separately by the owner
        // to authorize the ReferralModule, as PoolManager is not the owner of ReferralVoucher
        
        emit ReferralModuleSet(_referralModule);
    }

    // ============================================
    // ADMIN FUNCTIONS - AUTHORIZATION MANAGEMENT
    // ============================================

    /// @notice Authorizes a LiquidityManager contract to record liquidity additions
    /// @param manager Address to authorize
    function addAuthorizedLiquidityManager(address manager) external onlyOwner {
        if (manager == address(0)) revert InvalidAddress();
        authorizedLiquidityManagers[manager] = true;
        emit LiquidityManagerAuthorized(manager);
    }

    /// @notice Removes authorization from a LiquidityManager contract
    /// @param manager Address to deauthorize
    function removeAuthorizedLiquidityManager(
        address manager
    ) external onlyOwner {
        if (manager == address(0)) revert InvalidAddress();
        authorizedLiquidityManagers[manager] = false;
        emit LiquidityManagerDeauthorized(manager);
    }

    // ============================================
    // CROSS-CONTRACT HOOKS
    // ============================================

    /// @notice Records liquidity added to Uniswap (callback from LiquidityManager)
    /// @param poolId The pool ID
    /// @param ecmAmount Amount of ECM added to Uniswap
    /// @param usdtAmount Amount of USDT added to Uniswap
    function recordLiquidityAdded(
        uint256 poolId,
        uint256 ecmAmount,
        uint256 usdtAmount
    ) external {
        if (!authorizedLiquidityManagers[msg.sender])
            revert NotAuthorizedLiquidityManager();
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        pool.ecmAddedToUniswap += ecmAmount;
        pool.usdtAddedToUniswap += usdtAmount;

        emit LiquidityAddedToUniswap(poolId, ecmAmount, usdtAmount);
    }

    // ============================================
    // ADMIN FUNCTIONS - LIQUIDITY & EMERGENCYInvalidAmount
    // ============================================

    /// @notice Transfers tokens to LiquidityManager
    /// @param poolId The pool ID
    /// @param liquidityManager Address of the LiquidityManager
    /// @param ecmAmount Amount of ECM to transfer
    /// @param usdtAmount Amount of USDT to transfer
    function transferToLiquidityManager(
        uint256 poolId,
        address liquidityManager,
        uint256 ecmAmount,
        uint256 usdtAmount
    ) external onlyOwner {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        Pool storage pool = pools[poolId];

        // Admin can only transfer ECM up to the total staked amount, but do not subtract from totalStaked
        if (ecmAmount > pool.totalStaked - pool.liquidityPoolOwedECM)
            revert InsufficientECMForLiquidityTransfer();
        pool.ecmMovedToLiquidity += ecmAmount;
        pool.liquidityPoolOwedECM += ecmAmount;
        pool.ecm.safeTransfer(liquidityManager, ecmAmount);

        // USDT logic remains unchanged
        if (usdtAmount > 0) {
            if (usdtAmount > pool.collectedUSDT) revert InvalidAmount();
            pool.collectedUSDT -= usdtAmount;
            pool.usdtMovedToLiquidity += usdtAmount;
            pool.usdt.safeTransfer(liquidityManager, usdtAmount);
        }

        emit LiquidityTransferToManager(
            poolId,
            liquidityManager,
            ecmAmount,
            usdtAmount
        );
    }

    /// @notice Allows authorized liquidity managers to return unused ECM to the pool
    /// @dev Only callable by addresses in the authorizedLiquidityManagers mapping
    /// @param poolId The pool ID to refill
    /// @param ecmAmount Amount of ECM to return to the pool
    function refillPoolManager(uint256 poolId, uint256 ecmAmount) external {
        if (!authorizedLiquidityManagers[msg.sender])
            revert NotAuthorizedLiquidityManager();
        if (poolId >= poolCount) revert PoolDoesNotExist();
        Pool storage pool = pools[poolId];

        if (ecmAmount == 0) revert InvalidAmount();
        if (ecmAmount > pool.liquidityPoolOwedECM) revert InvalidAmount();

        pool.liquidityPoolOwedECM -= ecmAmount;
        pool.ecm.safeTransferFrom(msg.sender, address(this), ecmAmount);

        emit OwedLiquidityRefilled(poolId, ecmAmount);
    }

    /// @notice Emergency withdraw mistakenly sent tokens
    /// @param token Token address
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyRecoverTokens(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        // Add checks to prevent withdrawing user-staked tokens
        // This is a simplified version - production should have more robust checks
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Pauses all operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses all operations
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    // INTERNAL HELPER FUNCTIONS - BUY & STAKE
    // ============================================

    /// @notice Validates buy and stake parameters
    /// @param poolId The pool ID
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @param selectedStakeDuration Selected staking duration
    function _validateBuyAndStakeParams(
        uint256 poolId,
        uint256 maxUsdtAmount,
        uint256 selectedStakeDuration
    ) internal view {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (maxUsdtAmount == 0) revert InvalidAmount();

        Pool storage pool = pools[poolId];
        if (!pool.active) revert PoolNotActive();
        if (!_isAllowedDuration(poolId, selectedStakeDuration))
            revert InvalidStakeDuration();
    }

    /// @notice Calculates purchase amounts for buy and stake
    /// @param poolId The pool ID
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @return ecmToAllocate ECM amount to allocate
    /// @return usdtRequired USDT amount required
    function _calculatePurchaseAmounts(
        uint256 poolId,
        uint256 maxUsdtAmount
    ) internal view returns (uint256 ecmToAllocate, uint256 usdtRequired) {
        Pool storage pool = pools[poolId];

        // Get price and calculate ECM amount
        ecmToAllocate = _getECMAmountOut(poolId, maxUsdtAmount);

        // Check minimum purchase
        if (ecmToAllocate < MIN_PURCHASE_ECM) revert MinPurchaseNotMet();

        // Check pool inventory
        if (ecmToAllocate > pool.allocatedForSale - pool.sold)
            revert InsufficientPoolECM();

        // Calculate exact USDT required
        usdtRequired = _getUSDTAmountIn(poolId, ecmToAllocate);

        // Slippage check
        if (usdtRequired > maxUsdtAmount) revert SlippageExceeded();
    }

    /// @notice Executes the purchase transaction
    /// @param poolId The pool ID
    /// @param usdtRequired USDT amount required
    /// @param ecmToAllocate ECM amount to allocate
    function _executePurchase(
        uint256 poolId,
        uint256 usdtRequired,
        uint256 ecmToAllocate
    ) internal {
        Pool storage pool = pools[poolId];

        // Transfer USDT from user
        pool.usdt.safeTransferFrom(msg.sender, address(this), usdtRequired);

        // Update pool accounting
        pool.sold += ecmToAllocate;
        pool.collectedUSDT += usdtRequired;
    }

    /// @notice Handles referral voucher processing
    /// @param poolId The pool ID
    /// @param ecmToAllocate ECM amount to allocate
    /// @param voucherInput Referral voucher data
    /// @param voucherSignature EIP-712 signature for voucher
    /// @return referrer Referrer address
    /// @return codeHash Code hash
    function _handleReferralVoucher(
        uint256 poolId,
        uint256 ecmToAllocate,
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) internal returns (address referrer, bytes32 codeHash) {
        Pool storage pool = pools[poolId];
        
        if (address(referralVoucher) != address(0) && voucherInput.vid != bytes32(0)) {
            IReferralVoucher.VoucherResult memory voucherResult = referralVoucher.verifyAndConsume(
                voucherInput,
                voucherSignature,
                msg.sender
            );
            referrer = voucherResult.owner;
            codeHash = voucherResult.codeHash;

            // Record purchase and pay/accrue direct commission
            if (address(referralModule) != address(0)) {
                referralModule.recordPurchaseAndPayDirect(
                    codeHash,
                    msg.sender,
                    referrer,
                    poolId,
                    ecmToAllocate,
                    address(pool.ecm),
                    voucherResult.directBps,
                    voucherResult.transferOnUse
                );
            }
        }
    }

    /// @notice Validates buy exact ECM parameters
    /// @param poolId The pool ID
    /// @param exactEcmAmount Exact ECM amount to buy
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @param selectedStakeDuration Selected staking duration
    function _validateBuyExactECMParams(
        uint256 poolId,
        uint256 exactEcmAmount,
        uint256 maxUsdtAmount,
        uint256 selectedStakeDuration
    ) internal view {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (exactEcmAmount == 0) revert InvalidAmount();
        if (exactEcmAmount < MIN_PURCHASE_ECM) revert MinPurchaseNotMet();
        if (maxUsdtAmount == 0) revert InvalidAmount();

        Pool storage pool = pools[poolId];
        if (!pool.active) revert PoolNotActive();
        if (!_isAllowedDuration(poolId, selectedStakeDuration))
            revert InvalidStakeDuration();
    }

    /// @notice Calculates and validates exact ECM purchase
    /// @param poolId The pool ID
    /// @param exactEcmAmount Exact ECM amount to buy
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @return usdtRequired USDT amount required
    function _calculateExactECMPurchase(
        uint256 poolId,
        uint256 exactEcmAmount,
        uint256 maxUsdtAmount
    ) internal view returns (uint256 usdtRequired) {
        Pool storage pool = pools[poolId];

        // Check pool inventory
        if (exactEcmAmount > pool.allocatedForSale - pool.sold)
            revert InsufficientPoolECM();

        // Calculate exact USDT required
        usdtRequired = _getUSDTAmountIn(poolId, exactEcmAmount);

        // Slippage check
        if (usdtRequired > maxUsdtAmount) revert SlippageExceeded();
    }

    /// @notice Executes auto-staking logic
    /// @param poolId The pool ID
    /// @param ecmToAllocate ECM amount to stake
    /// @param selectedStakeDuration Selected staking duration
    function _executeAutoStake(
        uint256 poolId,
        uint256 ecmToAllocate,
        uint256 selectedStakeDuration
    ) internal {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        // Track unique stakers
        if (!user.hasStaked) {
            user.hasStaked = true;
            user.firstStakeTimestamp = block.timestamp;
            ++pool.totalUniqueStakers;
        }

        // If user already has stake, accumulate pending rewards
        if (user.staked > 0) {
            uint256 accumulated = (user.staked * pool.accRewardPerShare) / PRECISION;
            if (accumulated > user.rewardDebt) {
                uint256 pending = accumulated - user.rewardDebt;
                user.pendingRewards += pending;
            }
        }

        // Auto-stake
        user.staked += ecmToAllocate;
        user.stakeStart = block.timestamp;
        user.stakeDuration = selectedStakeDuration;
        pool.totalStaked += ecmToAllocate;
        user.rewardDebt = (user.staked * pool.accRewardPerShare) / PRECISION;

        // Update historical tracking
        user.totalStaked += ecmToAllocate;
        user.lastActionTimestamp = block.timestamp;
        pool.lifetimeStakeVolume += ecmToAllocate;

        // Update peak staked if necessary
        if (pool.totalStaked > pool.peakTotalStaked) {
            pool.peakTotalStaked = pool.totalStaked;
        }
    }

    // ============================================
    // USER FUNCTIONS - BUY & STAKE
    // ============================================

    /// @notice Buy ECM with USDT and auto-stake in a single transaction
    /// @param poolId The pool ID
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @param selectedStakeDuration Selected staking duration
    /// @param voucherInput Referral voucher data (optional - use zero values if no referral)
    /// @param voucherSignature EIP-712 signature for voucher (optional)
    function buyAndStake(
        uint256 poolId,
        uint256 maxUsdtAmount,
        uint256 selectedStakeDuration,
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) external nonReentrant whenNotPaused {
        // Basic parameter validation
        _validateBuyAndStakeParams(poolId, maxUsdtAmount, selectedStakeDuration);

        // Update pool rewards before any changes
        _updatePoolRewards(poolId);

        // Calculate purchase amounts
        (uint256 ecmToAllocate, uint256 usdtRequired) = _calculatePurchaseAmounts(poolId, maxUsdtAmount);

        // Execute purchase transaction
        _executePurchase(poolId, usdtRequired, ecmToAllocate);

        // Handle referral voucher
        (address referrer, bytes32 codeHash) = _handleReferralVoucher(
            poolId,
            ecmToAllocate,
            voucherInput,
            voucherSignature
        );

        // Execute auto-staking
        _executeAutoStake(poolId, ecmToAllocate, selectedStakeDuration);

        emit BoughtAndStaked(
            poolId,
            msg.sender,
            ecmToAllocate,
            usdtRequired,
            selectedStakeDuration,
            referrer,
            codeHash
        );
    }

    /// @notice Buy exact ECM amount and auto-stake
    /// @param poolId The pool ID
    /// @param exactEcmAmount Exact ECM amount to buy (minimum 500 ECM)
    /// @param maxUsdtAmount Maximum USDT willing to spend
    /// @param selectedStakeDuration Selected staking duration
    /// @param voucherInput Referral voucher data (optional - use zero values if no referral)
    /// @param voucherSignature EIP-712 signature for voucher (optional)
    function buyExactECMAndStake(
        uint256 poolId,
        uint256 exactEcmAmount,
        uint256 maxUsdtAmount,
        uint256 selectedStakeDuration,
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) external nonReentrant whenNotPaused {
        // Validate exact ECM specific parameters
        _validateBuyExactECMParams(poolId, exactEcmAmount, maxUsdtAmount, selectedStakeDuration);

        // Update pool rewards before any changes
        _updatePoolRewards(poolId);

        // Calculate and validate exact purchase amounts
        uint256 usdtRequired = _calculateExactECMPurchase(poolId, exactEcmAmount, maxUsdtAmount);

        // Execute purchase transaction
        _executePurchase(poolId, usdtRequired, exactEcmAmount);

        // Handle referral voucher
        (address referrer, bytes32 codeHash) = _handleReferralVoucher(
            poolId,
            exactEcmAmount,
            voucherInput,
            voucherSignature
        );

        // Execute auto-staking
        _executeAutoStake(poolId, exactEcmAmount, selectedStakeDuration);

        emit BoughtAndStaked(
            poolId,
            msg.sender,
            exactEcmAmount,
            usdtRequired,
            selectedStakeDuration,
            referrer,
            codeHash
        );
    }

    /// @notice Validates stake ECM parameters
    /// @param poolId The pool ID
    /// @param ecmAmount ECM amount to stake
    /// @param selectedStakeDuration Selected staking duration
    function _validateStakeECMParams(
        uint256 poolId,
        uint256 ecmAmount,
        uint256 selectedStakeDuration
    ) internal view {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        if (ecmAmount == 0) revert InvalidAmount();
        if (ecmAmount < MIN_PURCHASE_ECM) revert MinPurchaseNotMet();

        Pool storage pool = pools[poolId];
        if (!pool.active) revert PoolNotActive();
        if (!_isAllowedDuration(poolId, selectedStakeDuration))
            revert InvalidStakeDuration();
    }

    /// @notice Stake ECM tokens directly (for users who already own ECM)
    /// @param poolId The pool ID
    /// @param ecmAmount Amount of ECM to stake (minimum 500 ECM)
    /// @param selectedStakeDuration Selected staking duration
    function stakeECM(
        uint256 poolId,
        uint256 ecmAmount,
        uint256 selectedStakeDuration
    ) external nonReentrant whenNotPaused {
        // Parameter validation
        _validateStakeECMParams(poolId, ecmAmount, selectedStakeDuration);

        Pool storage pool = pools[poolId];

        // Update pool rewards
        _updatePoolRewards(poolId);

        // Transfer ECM from user
        pool.ecm.safeTransferFrom(msg.sender, address(this), ecmAmount);

        // Execute staking using helper function
        _executeAutoStake(poolId, ecmAmount, selectedStakeDuration);

        emit ECMStaked(poolId, msg.sender, ecmAmount, selectedStakeDuration);
    }

    // ============================================
    // USER FUNCTIONS - UNSTAKE & CLAIM
    // ============================================

    /// @notice Unstake tokens and claim rewards
    /// @param poolId The pool ID
    function unstake(uint256 poolId) external nonReentrant {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        if (user.staked == 0) revert NotStaked();

        // Update pool rewards
        _updatePoolRewards(poolId);

        // Calculate pending rewards safely
        uint256 accumulated = (user.staked * pool.accRewardPerShare) /
            PRECISION;
        uint256 pending = user.pendingRewards;
        if (accumulated > user.rewardDebt) {
            pending += accumulated - user.rewardDebt;
        }

        // Determine if matured
        bool matured = block.timestamp >= user.stakeStart + user.stakeDuration;

        uint256 principalToReturn;
        uint256 slashed = 0;

        if (matured) {
            // Full principal returned
            principalToReturn = user.staked;
        } else {
            // Early unstake - slash principal
            slashed = (user.staked * pool.penaltyBps) / MAX_BPS;
            principalToReturn = user.staked - slashed;
        }
        // Do not revert if rewards are depleted — allow principal unstake.
        // `_claimOrVestRewards` will clip the reward amount to remaining available rewards.

        // Update state before transfers
        uint256 stakedAmount = user.staked;
        pool.totalStaked -= user.staked;
        pool.lifetimeUnstakeVolume += principalToReturn; // Track unstake volume

        user.staked = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
        user.stakeStart = 0;
        user.stakeDuration = 0;

        // Update historical tracking
        user.totalUnstaked += stakedAmount;
        user.lastActionTimestamp = block.timestamp;

        if (slashed > 0) {
            user.totalPenaltiesPaid += slashed;
            pool.totalPenaltiesCollected += slashed;
        }

        // Transfer slashed tokens to penalty receiver
        if (slashed > 0 && pool.penaltyReceiver != address(0)) {
            pool.ecm.safeTransfer(pool.penaltyReceiver, slashed);
        }

        // Transfer principal to user
        if (principalToReturn > 0) {
            pool.ecm.safeTransfer(msg.sender, principalToReturn);
        }

        // Handle rewards (claim or vest). Use actual paid amount returned to avoid overcounting
        uint256 paid = 0;
        if (pending > 0) {
            paid = _claimOrVestRewards(poolId, msg.sender, pending);
            if (paid > 0) user.totalRewardsClaimed += paid;
        }

        // Emit appropriate event
        if (slashed > 0) {
            emit EarlyUnstaked(
                poolId,
                msg.sender,
                principalToReturn,
                slashed,
                paid
            );
        } else {
            emit Unstaked(poolId, msg.sender, principalToReturn, paid);
        }
    }

    /// @notice Claim rewards without unstaking
    /// @param poolId The pool ID
    function claimRewards(uint256 poolId) external nonReentrant {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        // Update pool rewards
        _updatePoolRewards(poolId);

        // Calculate pending rewards safely
        uint256 accumulated = (user.staked * pool.accRewardPerShare) /
            PRECISION;
        uint256 pending = user.pendingRewards;
        if (accumulated > user.rewardDebt) {
            pending += accumulated - user.rewardDebt;
        }

        if (pending == 0) return;

        // Update state
        user.rewardDebt = (user.staked * pool.accRewardPerShare) / PRECISION;
        user.pendingRewards = 0;

        // Transfer or vest rewards (based on pool configuration)
        uint256 paid = _claimOrVestRewards(poolId, msg.sender, pending);

        // Update historical tracking with actual paid amount
        if (paid > 0) {
            user.totalRewardsClaimed += paid;
            user.lastActionTimestamp = block.timestamp;

            // Record reward claim event for referral module (for off-chain engine)
            if (address(referralModule) != address(0)) {
                referralModule.recordRewardClaimEvent(
                    msg.sender,
                    poolId,
                    paid
                );
            }
        }
    }

    /// @notice Allows user to set their referrer after initial purchase (one-time only)
    /// @param voucherInput Referral voucher data
    /// @param voucherSignature EIP-712 signature for voucher
    /// @dev Can only be called if user has no referrer set
    function setMyReferrer(
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) external nonReentrant whenNotPaused {
        // Delegate to ReferralModule with explicit user address
        if (address(referralModule) != address(0)) {
            referralModule.setMyReferrerFor(msg.sender, voucherInput, voucherSignature);
        }
    }

    // ============================================
    // VIEW FUNCTIONS - PRICES
    // ============================================

    /// @notice Gets spot price from Uniswap reserves
    /// @param poolId The pool ID
    /// @return usdtPerEcm Price in USDT per ECM (scaled by PRECISION)
    /// @return reserveECM ECM reserve
    /// @return reserveUSDT USDT reserve
    function getPriceSpot(
        uint256 poolId
    )
        public
        view
        returns (uint256 usdtPerEcm, uint256 reserveECM, uint256 reserveUSDT)
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, ) = pool.pair.getReserves();

        address token0 = pool.pair.token0();

        if (token0 == address(pool.ecm)) {
            reserveECM = uint256(reserve0);
            reserveUSDT = uint256(reserve1);
        } else {
            reserveECM = uint256(reserve1);
            reserveUSDT = uint256(reserve0);
        }

        if (reserveECM > 0) {
            usdtPerEcm = (reserveUSDT * PRECISION) / reserveECM;
        }
    }

    // ============================================
    // VIEW FUNCTIONS - POOL & USER INFO
    // ============================================

    /// @notice Gets pool information
    /// @param poolId The pool ID
    /// @return pool Pool struct
    function getPoolInfo(
        uint256 poolId
    ) external view returns (Pool memory pool) {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        return pools[poolId];
    }

    /// @notice Gets user information
    /// @param poolId The pool ID
    /// @param user User address
    /// @return userInformation User struct
    function getUserInfo(
        uint256 poolId,
        address user
    ) external view returns (UserInfo memory userInformation) {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        return userInfo[poolId][user];
    }

    /// @notice Calculates pending rewards for a user
    /// @param poolId The pool ID
    /// @param user User address
    /// @return pending Pending reward amount
    function pendingRewards(
        uint256 poolId,
        address user
    ) public view returns (uint256 pending) {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage userInf = userInfo[poolId][user];

        if (userInf.staked == 0) return 0;

        uint256 accRewardPerShare = pool.accRewardPerShare;

        // Calculate updated accRewardPerShare, but cap to user's maturity time
        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 currentTime = block.timestamp;
            uint256 userMaturityTime = userInf.stakeStart + userInf.stakeDuration;
            
            // 🚨 CRITICAL FIX: Only calculate rewards up to user's maturity time
            if (userMaturityTime < currentTime) {
                currentTime = userMaturityTime;
            }
            
            if (currentTime > pool.lastRewardTime) {
                uint256 delta = currentTime - pool.lastRewardTime;
                uint256 rewardAccrued = _calculateRewardAccruedView(pool, delta);
                // Single PRECISION scaling - consistent with _updatePoolRewards
                accRewardPerShare += (rewardAccrued * PRECISION) / pool.totalStaked;
            }
        }

        pending =
            ((userInf.staked * accRewardPerShare) / PRECISION) -
            userInf.rewardDebt +
            userInf.pendingRewards;
    }

    /// @notice Estimates USDT required for exact ECM amount
    /// @param poolId The pool ID
    /// @param exactEcm Exact ECM amount
    /// @return usdtRequired USDT required
    function getRequiredUSDTForExactECM(
        uint256 poolId,
        uint256 exactEcm
    ) external view returns (uint256 usdtRequired) {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        return _getUSDTAmountIn(poolId, exactEcm);
    }

    /// @notice Estimates ECM for USDT amount
    /// @param poolId The pool ID
    /// @param usdtAmount USDT amount
    /// @return ecmEstimate Estimated ECM amount
    function estimateECMForUSDT(
        uint256 poolId,
        uint256 usdtAmount
    ) external view returns (uint256 ecmEstimate) {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        return _getECMAmountOut(poolId, usdtAmount);
    }

    /// @notice Gets comprehensive balance status for a pool
    /// @param poolId The pool ID
    /// @return totalAllocated Total ECM allocated (sale + rewards)
    /// @return soldToUsers ECM sold to users
    /// @return currentlyStaked ECM currently staked
    /// @return movedToLiquidity ECM moved to LiquidityManager
    /// @return liquidityOwedECM ECM owed to LiquidityManager
    /// @return addedToUniswap ECM actually added to Uniswap
    /// @return vested ECM vested through VestingManager
    /// @return rewardsPaid Total rewards paid out
    /// @return availableInContract ECM available in this contract
    /// @return deficit ECM deficit (if negative balance)
    function getPoolBalanceStatus(
        uint256 poolId
    )
        external
        view
        returns (
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
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];

        totalAllocated = pool.allocatedForSale + pool.allocatedForRewards;
        soldToUsers = pool.sold;
        currentlyStaked = pool.totalStaked;
        movedToLiquidity = pool.ecmMovedToLiquidity;
        liquidityOwedECM = pool.liquidityPoolOwedECM;
        addedToUniswap = pool.ecmAddedToUniswap;
        vested = pool.ecmVested;
        rewardsPaid = pool.rewardsPaid;

        // Calculate actual balance in contract
        uint256 contractBalance = pool.ecm.balanceOf(address(this));

        // Correct calculation:
        // (Total tokens ever received) - (Tokens no longer in contract)
        // Tokens no longer in contract:
        // - rewardsPaid: rewards paid/vested to users
        // - liquidityOwedECM: ECM transferred to LiquidityManager
        // - lifetimeUnstakeVolume: principal returned to users on unstake
        // - totalPenaltiesCollected: penalties sent to penaltyReceiver
        // Use the net outstanding liquidity owed (liquidityOwedECM) rather than
        // the cumulative moved amount so that refills are correctly reflected.
        uint256 totalOutflows = pool.rewardsPaid +
            liquidityOwedECM +
            pool.lifetimeUnstakeVolume +
            pool.totalPenaltiesCollected;
        
        uint256 totalInflows = pool.allocatedForSale + pool.allocatedForRewards;

        uint256 shouldHave;
        if (totalInflows >= totalOutflows) {
            shouldHave = totalInflows - totalOutflows;
        } else {
            // More outflows than inflows indicates an accounting issue
            shouldHave = 0;
        }

        if (contractBalance >= shouldHave) {
            availableInContract = contractBalance - shouldHave;
            deficit = 0;
        } else {
            availableInContract = 0;
            deficit = shouldHave - contractBalance;
        }
    }

    // ============================================
    // VIEW FUNCTIONS - ANALYTICS & METRICS
    // ============================================


    /// @notice Generic APR calculation for any reward strategy
    /// @param poolId The pool ID
    /// @param periodsToProject Number of periods to project (years for LINEAR as decimal 
    ///        scaled by PRECISION, months for MONTHLY, weeks for WEEKLY)
    /// @return apr Annual Percentage Rate (scaled by PRECISION)
    function calculateAPR(uint256 poolId, uint256 periodsToProject) public view returns (uint256 apr) {
        if (poolId >= poolCount) revert PoolDoesNotExist();
        Pool storage pool = pools[poolId];
        if (pool.totalStaked == 0) {
            return 0;
        }

        if (pool.rewardStrategy == RewardStrategy.LINEAR) {
            uint256 secondsPerYear = 31557600; // 365.25 days
            // periodsToProject represents years (scaled by 1e18, so 1e18 = 1 year, 5e17 = 0.5 year)
            uint256 periodRewards = (pool.rewardRatePerSecond * secondsPerYear * periodsToProject) / PRECISION;
            apr = (periodRewards * PRECISION * 100) / pool.totalStaked;
        } else if (pool.rewardStrategy == RewardStrategy.MONTHLY) {
            // Sum next N months of rewards
            uint256 projectedRewards = 0;
            for (uint256 i = 0; i < periodsToProject; ++i) {
                uint256 monthIndex = pool.monthlyRewardIndex + i;
                if (monthIndex < pool.monthlyRewards.length) {
                    projectedRewards += pool.monthlyRewards[monthIndex];
                }
            }
            // APR = (projectedRewards / totalStaked) * 100
            apr = (projectedRewards * PRECISION * 100) / pool.totalStaked;
        } else if (pool.rewardStrategy == RewardStrategy.WEEKLY) {
            // Sum next N weeks of rewards
            uint256 projectedRewards = 0;
            uint256 weeksProcessed = 0;
            uint256 currentWeekIndex = pool.weeklyRewardIndex;
            while (weeksProcessed < periodsToProject && currentWeekIndex < pool.weeklyRewards.length) {
                projectedRewards += pool.weeklyRewards[currentWeekIndex];
                ++weeksProcessed;
                ++currentWeekIndex;
            }

            apr = (projectedRewards * PRECISION * WEEKS_IN_YEAR * 100) / periodsToProject;
            apr = apr / pool.totalStaked;
        } else {
            apr = 0;
        }
    }

    /// @notice Calculate expected rewards for a user over a time period
    /// @param poolId The pool ID
    /// @param user User address
    /// @param durationSeconds Duration in seconds
    /// @return expectedRewards Expected ECM rewards
    function calculateExpectedRewards(
        uint256 poolId,
        address user,
        uint256 durationSeconds
    ) external view returns (uint256 expectedRewards) {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage userInf = userInfo[poolId][user];

        if (pool.totalStaked == 0 || userInf.staked == 0) {
            return 0;
        }

        if (pool.rewardStrategy == RewardStrategy.LINEAR) {
            // expectedRewards = (userStaked * rewardRatePerSecond * duration) / totalStaked
            expectedRewards =
                (userInf.staked * pool.rewardRatePerSecond * durationSeconds) /
                pool.totalStaked;
        } else if (pool.rewardStrategy == RewardStrategy.WEEKLY) {
            uint256 totalPoolRewards = 0;
            uint256 timeProcessed = 0;
            uint256 currentWeekIndex = pool.weeklyRewardIndex;
            uint256 currentTime = pool.lastRewardTime;

            // Process time across potentially multiple weeks
            while (
                timeProcessed < durationSeconds &&
                currentWeekIndex < pool.weeklyRewards.length
            ) {
                uint256 weekEndTime = pool.weeklyRewardStart +
                    (currentWeekIndex + 1) *
                    WEEK_SECONDS;
                uint256 timeLeftInDuration = durationSeconds - timeProcessed;

                if (currentTime >= weekEndTime) {
                    currentWeekIndex++;
                    currentTime = weekEndTime;
                    continue;
                }

                uint256 timeLeftInWeek = weekEndTime - currentTime;
                uint256 timeInThisWeek = timeLeftInDuration < timeLeftInWeek
                    ? timeLeftInDuration
                    : timeLeftInWeek;

                uint256 weekReward = pool.weeklyRewards[currentWeekIndex];
                uint256 rewardRate = (weekReward * PRECISION ) / WEEK_SECONDS;
                totalPoolRewards += (timeInThisWeek * rewardRate) / PRECISION;

                timeProcessed += timeInThisWeek;
                currentTime += timeInThisWeek;

                if (timeInThisWeek == timeLeftInWeek) {
                    currentWeekIndex++;
                    currentTime = weekEndTime;
                }
            }
            expectedRewards =
                (userInf.staked * totalPoolRewards) /
                pool.totalStaked;
        } else {
            // For MONTHLY, calculate using rate-per-second model across months
            uint256 totalPoolRewards = 0;
            uint256 timeProcessed = 0;
            uint256 currentMonthIndex = pool.monthlyRewardIndex;

            // Process time across potentially multiple months
            while (
                timeProcessed < durationSeconds &&
                currentMonthIndex < pool.monthlyRewards.length
            ) {
                uint256 timeInMonth;
                uint256 timeLeftInDuration = durationSeconds - timeProcessed;

                // Determine if we stay in current month or cross to next
                if (currentMonthIndex == pool.monthlyRewardIndex) {
                    // First month: may be partial
                    uint256 timeElapsedInMonth = block.timestamp -
                        pool.monthlyRewardStart -
                        (currentMonthIndex * 30 days);
                    uint256 timeLeftInMonth = 30 days - timeElapsedInMonth;
                    timeInMonth = timeLeftInDuration < timeLeftInMonth
                        ? timeLeftInDuration
                        : timeLeftInMonth;
                } else {
                    // Subsequent months: full or partial
                    timeInMonth = timeLeftInDuration < 30 days
                        ? timeLeftInDuration
                        : 30 days;
                }

                // Calculate rewards for this time period at this month's rate
                uint256 monthReward = pool.monthlyRewards[currentMonthIndex];
                uint256 rewardRate = (monthReward * PRECISION) / 30 days;
                totalPoolRewards += (timeInMonth * rewardRate) / PRECISION;

                timeProcessed += timeInMonth;
                ++currentMonthIndex;
            }

            // User's share of total pool rewards
            expectedRewards =
                (userInf.staked * totalPoolRewards) /
                pool.totalStaked;
        }
    }

    /// @notice Calculate ROI (Return on Investment) for a user
    /// @param poolId The pool ID
    /// @param user User address
    /// @param durationSeconds Time period for ROI calculation
    /// @param ecmPriceInUsdt Current ECM price in USDT (scaled by 1e18)
    /// @return roi Return on Investment percentage (scaled by 1e18, so 150% = 150e18)
    function calculateROI(
        uint256 poolId,
        address user,
        uint256 durationSeconds,
        uint256 ecmPriceInUsdt
    ) external view returns (uint256 roi) {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage userInf = userInfo[poolId][user];

        if (pool.totalStaked == 0 || userInf.staked == 0) {
            return 0;
        }

        // Calculate expected rewards
        uint256 expectedRewards;
        if (pool.rewardStrategy == RewardStrategy.LINEAR) {
            expectedRewards =
                (userInf.staked * pool.rewardRatePerSecond * durationSeconds) /
                pool.totalStaked;
        } else {
            // Use same logic as calculateExpectedRewards for MONTHLY
            uint256 totalPoolRewards = 0;
            uint256 timeProcessed = 0;
            uint256 currentMonthIndex = pool.monthlyRewardIndex;

            while (
                timeProcessed < durationSeconds &&
                currentMonthIndex < pool.monthlyRewards.length
            ) {
                uint256 timeInMonth;
                uint256 timeLeftInDuration = durationSeconds - timeProcessed;

                if (currentMonthIndex == pool.monthlyRewardIndex) {
                    uint256 timeElapsedInMonth = block.timestamp -
                        pool.monthlyRewardStart -
                        (currentMonthIndex * 30 days);
                    uint256 timeLeftInMonth = 30 days - timeElapsedInMonth;
                    timeInMonth = timeLeftInDuration < timeLeftInMonth
                        ? timeLeftInDuration
                        : timeLeftInMonth;
                } else {
                    timeInMonth = timeLeftInDuration < 30 days
                        ? timeLeftInDuration
                        : 30 days;
                }

                uint256 monthReward = pool.monthlyRewards[currentMonthIndex];
                uint256 rewardRate = (monthReward * PRECISION) / 30 days;
                totalPoolRewards += (timeInMonth * rewardRate) / PRECISION;

                timeProcessed += timeInMonth;
                currentMonthIndex++;
            }

            expectedRewards =
                (userInf.staked * totalPoolRewards) /
                pool.totalStaked;
        }

        // Calculate reward value in USDT
        uint256 rewardValueUsdt = (expectedRewards * ecmPriceInUsdt) /
            PRECISION;

        // Calculate investment value (assume user bought at current price)
        uint256 investmentUsdt = (userInf.staked * ecmPriceInUsdt) / PRECISION;

        if (investmentUsdt == 0) return 0;

        // ROI = (rewardValue / investment) * 100
        roi = (rewardValueUsdt * PRECISION * 100) / investmentUsdt;
    }

    /// @notice Calculate TVL (Total Value Locked) in USDT
    /// @param poolId The pool ID
    /// @param ecmPriceInUsdt Current ECM price in USDT (scaled by 1e18)
    /// @return tvl Total Value Locked in USDT (scaled by 1e6 for USDT decimals)
    function calculateTVL(
        uint256 poolId,
        uint256 ecmPriceInUsdt
    ) external view returns (uint256 tvl) {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];

        // TVL = totalStaked * ecmPrice
        // ecmPrice is scaled by 1e18, totalStaked by 1e18
        // Result scaled by 1e6 for USDT
        tvl = (pool.totalStaked * ecmPriceInUsdt) / (PRECISION * 1e12);
    }

    /// @notice Calculate pool utilization rate (percentage of allocated ECM sold)
    /// @param poolId The pool ID
    /// @return utilizationRate Percentage (scaled by 1e18, so 75% = 75e18)
    function calculateUtilizationRate(
        uint256 poolId
    ) external view returns (uint256 utilizationRate) {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];

        if (pool.allocatedForSale == 0) return 0;

        // Utilization = (sold / allocatedForSale) * PRECISION (1e18 = 100%)
        utilizationRate = (pool.sold * PRECISION) / pool.allocatedForSale;
    }

    /// @notice Calculate reward pool depletion time
    /// @param poolId The pool ID
    /// @return depletionTimestamp Estimated timestamp when rewards will be depleted (0 if infinite)
    /// @return daysRemaining Days until depletion
    /// @return isInfinite True if depletion is infinite (rate is 0)
    function calculateRewardDepletionTime(
        uint256 poolId
    )
        external
        view
        returns (
            uint256 depletionTimestamp,
            uint256 daysRemaining,
            bool isInfinite
        )
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];

        uint256 remainingRewards = pool.allocatedForRewards -
            pool.totalRewardsAccrued;

        if (pool.rewardStrategy == RewardStrategy.LINEAR) {
            if (pool.rewardRatePerSecond == 0) {
                return (0, 0, true);
            }

            uint256 secondsRemaining = remainingRewards /
                pool.rewardRatePerSecond;
            depletionTimestamp = block.timestamp + secondsRemaining;
            daysRemaining = secondsRemaining / 86400;
            isInfinite = false;
        } else {
            // For MONTHLY, calculate based on remaining months
            uint256 totalMonthlyRemaining = 0;
            uint256 monthlyRewardsLength = pool.monthlyRewards.length;
            for (
                uint256 i = pool.monthlyRewardIndex;
                i < monthlyRewardsLength;
                ++i
            ) {
                totalMonthlyRemaining += pool.monthlyRewards[i];
            }

            if (totalMonthlyRemaining == 0) {
                return (block.timestamp, 0, false);
            }

            uint256 monthsRemaining = pool.monthlyRewards.length -
                pool.monthlyRewardIndex;
            uint256 secondsRemaining = monthsRemaining * 30 days;
            depletionTimestamp = block.timestamp + secondsRemaining;
            daysRemaining = secondsRemaining / 86400;
            isInfinite = false;
        }
    }

    /// @notice Get comprehensive pool analytics
    /// @param poolId The pool ID
    /// @param ecmPriceInUsdt Current ECM price (scaled by 1e18)
    /// @return poolAge Pool age in seconds
    /// @return totalUniqueStakers Number of unique addresses that have staked
    /// @return totalPenaltiesCollected Total ECM collected from penalties
    /// @return peakTotalStaked Highest totalStaked value reached
    /// @return lifetimeStakeVolume Cumulative ECM staked
    /// @return lifetimeUnstakeVolume Cumulative ECM unstaked
    /// @return currentTVL Current TVL in USDT (scaled by 1e6)
    function getPoolAnalytics(
        uint256 poolId,
        uint256 ecmPriceInUsdt
    )
        external
        view
        returns (
            uint256 poolAge,
            uint256 totalUniqueStakers,
            uint256 totalPenaltiesCollected,
            uint256 peakTotalStaked,
            uint256 lifetimeStakeVolume,
            uint256 lifetimeUnstakeVolume,
            uint256 currentTVL
        )
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];

        poolAge = block.timestamp - pool.poolCreatedAt;
        totalUniqueStakers = pool.totalUniqueStakers;
        totalPenaltiesCollected = pool.totalPenaltiesCollected;
        peakTotalStaked = pool.peakTotalStaked;
        lifetimeStakeVolume = pool.lifetimeStakeVolume;
        lifetimeUnstakeVolume = pool.lifetimeUnstakeVolume;
        currentTVL = (pool.totalStaked * ecmPriceInUsdt) / (PRECISION * 1e12);
    }

    /// @notice Get comprehensive user analytics
    /// @param poolId The pool ID
    /// @param user User address
    /// @return hasStaked Whether user has ever staked
    /// @return firstStakeTimestamp Timestamp of first stake
    /// @return lastActionTimestamp Timestamp of last action
    /// @return totalStaked Lifetime total staked
    /// @return totalUnstaked Lifetime total unstaked
    /// @return totalRewardsClaimed Lifetime rewards claimed
    /// @return totalPenaltiesPaid Total penalties paid
    /// @return accountAge Age of user's account in pool (seconds)
    function getUserAnalytics(
        uint256 poolId,
        address user
    )
        external
        view
        returns (
            bool hasStaked,
            uint256 firstStakeTimestamp,
            uint256 lastActionTimestamp,
            uint256 totalStaked,
            uint256 totalUnstaked,
            uint256 totalRewardsClaimed,
            uint256 totalPenaltiesPaid,
            uint256 accountAge
        )
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        UserInfo storage userInf = userInfo[poolId][user];

        hasStaked = userInf.hasStaked;
        firstStakeTimestamp = userInf.firstStakeTimestamp;
        lastActionTimestamp = userInf.lastActionTimestamp;
        totalStaked = userInf.totalStaked;
        totalUnstaked = userInf.totalUnstaked;
        totalRewardsClaimed = userInf.totalRewardsClaimed;
        totalPenaltiesPaid = userInf.totalPenaltiesPaid;

        if (userInf.firstStakeTimestamp > 0) {
            accountAge = block.timestamp - userInf.firstStakeTimestamp;
        } else {
            accountAge = 0;
        }
    }

    /// @notice Calculate early unstake penalty for a user
    /// @param poolId The pool ID
    /// @param user User address
    /// @return willBePenalized Whether user will be penalized if unstaking now
    /// @return penaltyAmount Amount of ECM that will be slashed
    /// @return amountReceived Amount user will receive after penalty
    /// @return timeUntilMaturity Seconds until stake matures (0 if matured)
    function calculateUnstakePenalty(
        uint256 poolId,
        address user
    )
        external
        view
        returns (
            bool willBePenalized,
            uint256 penaltyAmount,
            uint256 amountReceived,
            uint256 timeUntilMaturity
        )
    {
        if (poolId >= poolCount) revert PoolDoesNotExist();

        Pool storage pool = pools[poolId];
        UserInfo storage userInf = userInfo[poolId][user];

        if (userInf.staked == 0) {
            return (false, 0, 0, 0);
        }

        uint256 maturityTime = userInf.stakeStart + userInf.stakeDuration;

        if (block.timestamp >= maturityTime) {
            // Matured - no penalty
            return (false, 0, userInf.staked, 0);
        } else {
            // Early unstake - calculate penalty
            willBePenalized = true;
            penaltyAmount = (userInf.staked * pool.penaltyBps) / MAX_BPS;
            amountReceived = userInf.staked - penaltyAmount;
            timeUntilMaturity = maturityTime - block.timestamp;
        }
    }

    // ============================================
    // INTERNAL FUNCTIONS - REWARDS
    // ============================================

    /**
     * @notice Updates pool reward variables using accRewardPerShare pattern
     * @dev CRITICAL: Must be called before ANY stake/unstake/claim operation
     * @custom:math accRewardPerShare += (rewardAccrued * 1e18) / totalStaked
     * @custom:purpose Tracks cumulative rewards per staked ECM, enables precise reward calculation for all users
     * @custom:scaling Uses 1e18 scaling to prevent precision loss in integer division
     * @custom:example If totalStaked = 1000 ECM, rewardAccrued = 10 ECM, then 
     *               accRewardPerShare increases by (10 * 1e18) / 1000
     * User with 100 staked gets: (100 * accRewardPerShare) / 1e18 = 1 ECM reward
     * Caps rewardAccrued to remaining rewards, disables accrual when depleted.
     * @param poolId The pool ID
     */
    function _updatePoolRewards(uint256 poolId) internal {
        Pool storage pool = pools[poolId];

        if (block.timestamp <= pool.lastRewardTime) return;

        if (pool.totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 delta = block.timestamp - pool.lastRewardTime;
        uint256 rewardAccrued = _calculateRewardAccrued(pool, delta);

        if (rewardAccrued > 0) {
            // Cap rewardAccrued to remaining rewards to prevent over-promising
            uint256 remainingRewards = pool.allocatedForRewards -
                pool.totalRewardsAccrued;
            if (rewardAccrued > remainingRewards) {
                rewardAccrued = remainingRewards;
                // Stop future reward accrual when depleted
                if (pool.rewardStrategy == RewardStrategy.LINEAR) {
                    pool.rewardRatePerSecond = 0;
                } else {
                    pool.monthlyRewardIndex = pool.monthlyRewards.length;
                }
            }

            // Track total accrued rewards
            pool.totalRewardsAccrued += rewardAccrued;

            if (pool.totalStaked > 0) {
                // Single PRECISION scaling for accRewardPerShare
                // accRewardPerShare represents rewards per token staked, scaled by PRECISION
                pool.accRewardPerShare +=
                    (rewardAccrued * PRECISION) / pool.totalStaked;
            }
        }

        pool.lastRewardTime = block.timestamp;
    }

    /// @notice Calculates reward accrued based on strategy
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return rewardAccrued Amount of reward accrued
    /// @dev NOT view - updates state for MONTHLY strategy
    function _calculateRewardAccrued(
        Pool storage pool,
        uint256 delta
    ) internal returns (uint256 rewardAccrued) {
        if (pool.rewardStrategy == RewardStrategy.WEEKLY) {
            rewardAccrued = _calculateWeeklyRewards(pool, delta);
        } else if (pool.rewardStrategy == RewardStrategy.MONTHLY) {
            rewardAccrued = _calculateMonthlyRewards(pool, delta);
        } else {
            // LINEAR: Simple multiplication - rate is already in tokens per second
            rewardAccrued = delta * pool.rewardRatePerSecond;
        }
    }

    /// @notice Calculates monthly rewards with proper month progression
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return totalRewards Total rewards for elapsed time
    /// @dev Updates monthlyRewardIndex as months pass, distributes rewards continuously
    function _calculateMonthlyRewards(
        Pool storage pool,
        uint256 delta
    ) internal returns (uint256 totalRewards) {
        if (pool.monthlyRewards.length == 0) return 0;
        if (pool.monthlyRewardIndex >= pool.monthlyRewards.length) return 0; // All months completed

        uint256 timeProcessed = 0;
        uint256 currentTime = pool.lastRewardTime;

        // Process time across potentially multiple months
        while (
            timeProcessed < delta &&
            pool.monthlyRewardIndex < pool.monthlyRewards.length
        ) {
            // Calculate when current month ends
            uint256 monthEndTime = pool.monthlyRewardStart +
                ((pool.monthlyRewardIndex + 1) * 30 days);
            uint256 timeLeftInDelta = delta - timeProcessed;

            if (currentTime + timeLeftInDelta <= monthEndTime) {
                // All remaining time is within current month
                uint256 monthReward = pool.monthlyRewards[
                    pool.monthlyRewardIndex
                ];
                // Calculate reward rate: tokens per second for this month (no pre-scaling)
                uint256 rewardRate = monthReward / 30 days;
                totalRewards += timeLeftInDelta * rewardRate;
                timeProcessed = delta; // Done processing
            } else {
                // Time crosses into next month
                uint256 timeInThisMonth = monthEndTime - currentTime;
                uint256 monthReward = pool.monthlyRewards[
                    pool.monthlyRewardIndex
                ];
                // Calculate reward rate: tokens per second for this month (no pre-scaling)
                uint256 rewardRate = monthReward / 30 days;
                totalRewards += timeInThisMonth * rewardRate;

                // Advance to next month
                pool.monthlyRewardIndex++;
                currentTime = monthEndTime;
                timeProcessed += timeInThisMonth;
            }
        }

        return totalRewards;
    }

    /// @notice Calculates weekly rewards with proper week progression
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return totalRewards Total rewards for elapsed time
    /// @dev Updates weeklyRewardIndex as weeks pass, distributes rewards continuously
    function _calculateWeeklyRewards(
        Pool storage pool,
        uint256 delta
    ) internal returns (uint256 totalRewards) {
        if (pool.weeklyRewards.length == 0) return 0;
        if (pool.weeklyRewardIndex >= pool.weeklyRewards.length) return 0;

        uint256 timeProcessed = 0;
        uint256 currentTime = pool.lastRewardTime;
        uint256 currentWeekIndex = pool.weeklyRewardIndex; // LOCAL copy

        while (
            timeProcessed < delta &&
            currentWeekIndex < pool.weeklyRewards.length
        ) {
            uint256 weekEndTime = pool.weeklyRewardStart +
                (currentWeekIndex + 1) *
                WEEK_SECONDS;

            uint256 timeLeftInDelta = delta - timeProcessed;
            if (currentTime >= weekEndTime) {
                // Time has already passed this week, move to next
                currentWeekIndex++;
                currentTime = weekEndTime;
                continue;
            }

            uint256 timeLeftInWeek = weekEndTime - currentTime;
            uint256 timeInThisWeek = timeLeftInDelta < timeLeftInWeek
                ? timeLeftInDelta
                : timeLeftInWeek;

            uint256 weekReward = pool.weeklyRewards[currentWeekIndex];
            // Calculate reward rate: tokens per second for this week (no pre-scaling)
            uint256 rewardRate = weekReward / WEEK_SECONDS;
            totalRewards += timeInThisWeek * rewardRate;

            timeProcessed += timeInThisWeek;
            currentTime += timeInThisWeek;

            if (timeInThisWeek == timeLeftInWeek) {
                // Move to next week
                currentWeekIndex++;
                currentTime = weekEndTime;
            }
        }

        // Update state variables
        pool.weeklyRewardIndex = currentWeekIndex;
        return totalRewards;
    }

    /// @notice Calculates weekly rewards WITHOUT modifying state (VIEW ONLY)
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return totalRewards Total rewards for elapsed time
    /// @dev View-only version - does NOT update weeklyRewardIndex
    function _calculateWeeklyRewardsView(
        Pool storage pool,
        uint256 delta
    ) internal view returns (uint256 totalRewards) {
        if (pool.weeklyRewards.length == 0) return 0;
        if (pool.weeklyRewardIndex >= pool.weeklyRewards.length) return 0;

        uint256 timeProcessed = 0;
        uint256 currentTime = pool.lastRewardTime;
        uint256 currentWeekIndex = pool.weeklyRewardIndex; // LOCAL copy

        while (
            timeProcessed < delta &&
            currentWeekIndex < pool.weeklyRewards.length
        ) {
            uint256 weekEndTime = pool.weeklyRewardStart +
                (currentWeekIndex + 1) *
                WEEK_SECONDS;

            uint256 timeLeftInDelta = delta - timeProcessed;
            if (currentTime >= weekEndTime) {
                currentWeekIndex++;
                currentTime = weekEndTime;
                continue;
            }

            uint256 timeLeftInWeek = weekEndTime - currentTime;
            uint256 timeInThisWeek = timeLeftInDelta < timeLeftInWeek
                ? timeLeftInDelta
                : timeLeftInWeek;

            uint256 weekReward = pool.weeklyRewards[currentWeekIndex];
            // Calculate reward rate: tokens per second for this week (no pre-scaling)
            uint256 rewardRate = weekReward / WEEK_SECONDS;
            totalRewards += timeInThisWeek * rewardRate;

            timeProcessed += timeInThisWeek;
            currentTime += timeInThisWeek;

            if (timeInThisWeek == timeLeftInWeek) {
                currentWeekIndex++;
                currentTime = weekEndTime;
            }
        }
        return totalRewards;
    }

    /// @notice Calculates reward accrued based on strategy (VIEW ONLY - no state changes)
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return rewardAccrued Amount of reward accrued
    /// @dev View-only version for pendingRewards() - does NOT update monthlyRewardIndex
    function _calculateRewardAccruedView(
        Pool storage pool,
        uint256 delta
    ) internal view returns (uint256 rewardAccrued) {
        if (pool.rewardStrategy == RewardStrategy.LINEAR) {
            // LINEAR: Simple multiplication - rate is already in tokens per second
            rewardAccrued = delta * pool.rewardRatePerSecond;
        } else if (pool.rewardStrategy == RewardStrategy.WEEKLY) {
            // WEEKLY strategy - view-only calculation (no state updates)
            rewardAccrued = _calculateWeeklyRewardsView(pool, delta);
        } else {
            // MONTHLY strategy - view-only calculation (no state updates)
            rewardAccrued = _calculateMonthlyRewardsView(pool, delta);
        }

        // 🚨 CRITICAL FIX: Apply the same capping logic as _updatePoolRewards
        // Prevent view functions from showing unlimited rewards
        uint256 remainingRewards = pool.allocatedForRewards - pool.totalRewardsAccrued;
        if (rewardAccrued > remainingRewards) {
            rewardAccrued = remainingRewards;
        }
    }

    /// @notice Calculates monthly rewards WITHOUT modifying state (VIEW ONLY)
    /// @param pool Pool storage reference
    /// @param delta Time elapsed in seconds
    /// @return totalRewards Total rewards for elapsed time
    /// @dev View-only version - does NOT update monthlyRewardIndex
    function _calculateMonthlyRewardsView(
        Pool storage pool,
        uint256 delta
    ) internal view returns (uint256 totalRewards) {
        if (pool.monthlyRewards.length == 0) return 0;
        if (pool.monthlyRewardIndex >= pool.monthlyRewards.length) return 0;

        uint256 timeProcessed = 0;
        uint256 currentTime = pool.lastRewardTime;
        uint256 currentMonthIndex = pool.monthlyRewardIndex; // LOCAL copy - don't modify storage

        // Process time across potentially multiple months
        while (
            timeProcessed < delta &&
            currentMonthIndex < pool.monthlyRewards.length
        ) {
            // Calculate when current month ends
            uint256 monthEndTime = pool.monthlyRewardStart +
                ((currentMonthIndex + 1) * 30 days);
            uint256 timeLeftInDelta = delta - timeProcessed;

            if (currentTime + timeLeftInDelta <= monthEndTime) {
                // All remaining time is within current month
                uint256 monthReward = pool.monthlyRewards[currentMonthIndex];
                // Calculate reward rate: tokens per second for this month (no pre-scaling)
                uint256 rewardRate = monthReward / 30 days;
                totalRewards += timeLeftInDelta * rewardRate;
                timeProcessed = delta; // Done processing
            } else {
                // Time crosses into next month
                uint256 timeInThisMonth = monthEndTime - currentTime;
                uint256 monthReward = pool.monthlyRewards[currentMonthIndex];
                // Calculate reward rate: tokens per second for this month (no pre-scaling)
                uint256 rewardRate = monthReward / 30 days;
                totalRewards += timeInThisMonth * rewardRate;

                // Advance to next month (LOCAL variable only)
                currentMonthIndex++;
                currentTime = monthEndTime;
                timeProcessed += timeInThisMonth;
            }
        }

        return totalRewards;
    }

    /// @notice Claims or vests rewards for a user
    /// @param poolId The pool ID
    /// @param user User address
    /// @param amount Reward amount
    function _claimOrVestRewards(
        uint256 poolId,
        address user,
        uint256 amount
    ) internal returns (uint256 paidAmount) {
        Pool storage pool = pools[poolId];

        // Enforce hard limit on rewards
        uint256 remainingRewards = pool.allocatedForRewards - pool.rewardsPaid;
        if (amount > remainingRewards) {
            amount = remainingRewards;
            if (amount == 0) return 0; // No rewards left to claim
        }

        // Update rewardsPaid for ALL distributions (both immediate and vested)
        pool.rewardsPaid += amount;

        // Use pool's vesting configuration only
        bool shouldVest = pool.vestRewardsByDefault;
        if (
            shouldVest &&
            address(vestingManager) != address(0) &&
            pool.vestingDuration > 0
        ) {
            // Transfer tokens to VestingManager and create vesting schedule
            pool.ecm.safeTransfer(address(vestingManager), amount);
            uint256 vestingId;
            try
                vestingManager.createVesting(
                    user,
                    amount,
                    block.timestamp,
                    pool.vestingDuration,
                    address(pool.ecm),
                    poolId
                )
            returns (uint256 _vestingId) {
                vestingId = _vestingId;
                emit RewardsVested(
                    poolId,
                    user,
                    amount,
                    vestingId,
                    pool.vestingDuration
                );
            } catch {
                revert VestingFailed();
            }
            pool.ecmVested += amount;
        } else {
            // Direct transfer - track as paid rewards
            pool.ecm.safeTransfer(user, amount);
        }
        emit RewardsClaimed(poolId, user, amount, shouldVest);

        return amount;
    }

    // ============================================
    // INTERNAL FUNCTIONS - PRICING
    // ============================================

    /// @notice Calculates ECM amount out for USDT amount in using Uniswap V2 AMM formula
    /// @param poolId The pool ID
    /// @param usdtAmountIn USDT amount in
    /// @return ecmAmountOut ECM amount out
    /// @dev Uses spot price from Uniswap V2 pair reserves (NO TWAP)
    /// @dev Calculates locally using Uniswap V2 formula: 
    ///      (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    function _getECMAmountOut(
        uint256 poolId,
        uint256 usdtAmountIn
    ) internal view returns (uint256 ecmAmountOut) {
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, ) = pool.pair.getReserves();

        address token0 = pool.pair.token0();
        uint256 reserveIn;
        uint256 reserveOut;

        if (token0 == address(pool.usdt)) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }

        // Uniswap V2 formula with 0.3% fee (997/1000)
        // amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
        uint256 amountInWithFee = usdtAmountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        
        ecmAmountOut = numerator / denominator;
    }

    /// @notice Calculates USDT amount in for exact ECM amount out (inverse formula)
    /// @param poolId The pool ID
    /// @param ecmAmountOut ECM amount out
    /// @return usdtAmountIn USDT amount in
    /// @dev Inverse of _getECMAmountOut - calculates required USDT for exact ECM
    /// @dev Uses Uniswap V2 inverse formula: (reserveIn * amountOut * 1000) / (reserveOut - amountOut) * 997) + 1
    function _getUSDTAmountIn(
        uint256 poolId,
        uint256 ecmAmountOut
    ) internal view returns (uint256 usdtAmountIn) {
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, ) = pool.pair.getReserves();

        address token0 = pool.pair.token0();
        uint256 reserveIn;
        uint256 reserveOut;

        if (token0 == address(pool.usdt)) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }

        // Uniswap V2 inverse formula with 0.3% fee
        // amountIn = (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
        if (ecmAmountOut >= reserveOut) {
            revert InsufficientLiquidity();
        }
        
        uint256 numerator = reserveIn * ecmAmountOut * 1000;
        uint256 denominator = (reserveOut - ecmAmountOut) * 997;
        
        usdtAmountIn = (numerator / denominator) + 1; // +1 for rounding
    }

    // ============================================
    // INTERNAL FUNCTIONS - HELPERS
    // ============================================

    /// @notice Checks if stake duration is allowed
    /// @param poolId The pool ID
    /// @param duration Duration to check
    /// @return allowed Whether the duration is allowed
    function _isAllowedDuration(
        uint256 poolId,
        uint256 duration
    ) internal view returns (bool allowed) {
        Pool storage pool = pools[poolId];
        uint256[] memory durations = pool.allowedStakeDurations;
        uint256 durationsLength = durations.length;

        for (uint256 i = 0; i < durationsLength; ++i) {
            if (durations[i] == duration) {
                return true;
            }
        }

        return false;
    }
}
