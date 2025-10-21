// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPoolManager {
    function recordVesting(
        uint256 poolId,
        address user,
        uint256 amount,
        uint256 vestingId
    ) external;
}

/// @title VestingManager - Linear Token Vesting Contract
/// @notice Manages linear vesting schedules for ECM token rewards
/// @dev Called by PoolManager to create vesting entries; users claim vested tokens over time
contract VestingManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Vesting schedule structure
    struct VestingSchedule {
        address beneficiary; // Who receives the vested tokens
        address token; // Token being vested (ECM)
        uint256 poolId; // Associated pool ID (for callback)
        uint256 amount; // Total amount to vest
        uint256 start; // Vesting start timestamp
        uint256 duration; // Vesting duration in seconds
        uint256 claimed; // Amount already claimed
        bool revoked; // Whether vesting was revoked
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice PoolManager address for callbacks
    IPoolManager public poolManager;

    /// @notice Mapping of vesting ID to vesting schedule
    mapping(uint256 => VestingSchedule) public vestingSchedules;

    /// @notice Mapping of user address to their vesting IDs
    mapping(address => uint256[]) public userVestingIds;

    /// @notice Next vesting ID to be assigned
    uint256 public nextVestingId;

    /// @notice Addresses authorized to create vesting schedules (e.g., PoolManager)
    mapping(address => bool) public authorizedCreators;

    /// @notice Total vested amount per token
    mapping(address => uint256) public totalVestedAmount;

    /// @notice Total claimed amount per token
    mapping(address => uint256) public totalClaimedAmount;

    // ============================================
    // EVENTS
    // ============================================

    event VestingCreated(
        uint256 indexed vestingId,
        address indexed beneficiary,
        address indexed token,
        uint256 amount,
        uint256 start,
        uint256 duration
    );

    event VestedClaimed(
        uint256 indexed vestingId,
        address indexed beneficiary,
        address indexed token,
        uint256 amount
    );

    event VestingRevoked(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 amountVested,
        uint256 amountRefunded
    );

    event AuthorizedCreatorAdded(address indexed creator);
    event AuthorizedCreatorRemoved(address indexed creator);

    event EmergencyWithdraw(
        address indexed token,
        uint256 amount,
        address indexed to
    );

    // ============================================
    // ERRORS
    // ============================================

    error NotAuthorized();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidToken();
    error VestingNotFound();
    error NotBeneficiary();
    error NothingToClaim();
    error AlreadyRevoked();
    error InsufficientBalance();
    error VestingNotStarted();

    // ============================================
    // MODIFIERS
    // ============================================

    /// @notice Restricts function to authorized creators only
    modifier onlyAuthorized() {
        if (!authorizedCreators[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _poolManager) Ownable(msg.sender) {
        if (_poolManager != address(0)) {
            poolManager = IPoolManager(_poolManager);
        }
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /// @notice Adds an authorized creator (e.g., PoolManager)
    /// @param creator Address to authorize
    function addAuthorizedCreator(address creator) external onlyOwner {
        if (creator == address(0)) revert InvalidBeneficiary();
        authorizedCreators[creator] = true;
        emit AuthorizedCreatorAdded(creator);
    }

    /// @notice Removes an authorized creator
    /// @param creator Address to deauthorize
    function removeAuthorizedCreator(address creator) external onlyOwner {
        authorizedCreators[creator] = false;
        emit AuthorizedCreatorRemoved(creator);
    }

    /// @notice Emergency withdraw tokens (only for unclaimed/stuck tokens)
    /// @dev Should only be used in emergency situations
    /// @param token Token address
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) revert InvalidBeneficiary();

        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, amount, to);
    }

    // ============================================
    // VESTING CREATION
    // ============================================

    /// @notice Creates a new vesting schedule
    /// @dev Only callable by authorized creators (e.g., PoolManager)
    /// @param beneficiary Address that will receive vested tokens
    /// @param amount Total amount to vest
    /// @param start Vesting start timestamp
    /// @param duration Vesting duration in seconds
    /// @param token Token address being vested (ECM)
    /// @param poolId Associated pool ID (for callback to PoolManager)
    /// @return vestingId The ID of the created vesting schedule
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 start,
        uint256 duration,
        address token,
        uint256 poolId
    ) external onlyAuthorized nonReentrant returns (uint256 vestingId) {
        // Validation
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();

        // Note: Tokens should be transferred to this contract BEFORE calling this function

        vestingId = nextVestingId++;

        vestingSchedules[vestingId] = VestingSchedule({
            beneficiary: beneficiary,
            token: token,
            poolId: poolId,
            amount: amount,
            start: start,
            duration: duration,
            claimed: 0,
            revoked: false
        });

        userVestingIds[beneficiary].push(vestingId);
        totalVestedAmount[token] += amount;

        emit VestingCreated(
            vestingId,
            beneficiary,
            token,
            amount,
            start,
            duration
        );

        return vestingId;
    }

    /// @notice Creates a vesting schedule with explicit token address
    /// @param beneficiary Address that will receive vested tokens
    /// @param token Token address being vested
    /// @param amount Total amount to vest
    /// @param start Vesting start timestamp
    /// @param duration Vesting duration in seconds
    /// @return vestingId The ID of the created vesting schedule
    function createVestingWithToken(
        address beneficiary,
        address token,
        uint256 amount,
        uint256 start,
        uint256 duration,
        uint256 poolId
    ) external onlyAuthorized nonReentrant returns (uint256 vestingId) {
        // Validation
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();

        vestingId = nextVestingId++;

        vestingSchedules[vestingId] = VestingSchedule({
            beneficiary: beneficiary,
            token: token,
            poolId: poolId,
            amount: amount,
            start: start,
            duration: duration,
            claimed: 0,
            revoked: false
        });

        userVestingIds[beneficiary].push(vestingId);
        totalVestedAmount[token] += amount;

        emit VestingCreated(
            vestingId,
            beneficiary,
            token,
            amount,
            start,
            duration
        );

        return vestingId;
    }

    // ============================================
    // USER FUNCTIONS
    // ============================================

    /// @notice Claims vested tokens for a specific vesting schedule
    /// @param vestingId The vesting schedule ID
    function claimVested(uint256 vestingId) external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[vestingId];

        // Validation
        if (schedule.beneficiary == address(0)) revert VestingNotFound();
        if (schedule.beneficiary != msg.sender) revert NotBeneficiary();
        if (schedule.revoked) revert AlreadyRevoked();

        // Calculate vested amount
        uint256 vested = _calculateVested(schedule);
        uint256 claimable = vested - schedule.claimed;

        if (claimable == 0) revert NothingToClaim();

        // Update state
        schedule.claimed += claimable;
        totalClaimedAmount[schedule.token] += claimable;

        // Transfer tokens
        IERC20(schedule.token).safeTransfer(msg.sender, claimable);

        emit VestedClaimed(vestingId, msg.sender, schedule.token, claimable);
    }

    /// @notice Claims all available vested tokens for the caller
    /// @dev Iterates through all vesting schedules for the user
    function claimAllVested() external nonReentrant {
        uint256[] memory vestingIds = userVestingIds[msg.sender];

        for (uint256 i = 0; i < vestingIds.length; i++) {
            uint256 vestingId = vestingIds[i];
            VestingSchedule storage schedule = vestingSchedules[vestingId];

            // Skip if revoked or already fully claimed
            if (schedule.revoked || schedule.claimed >= schedule.amount) {
                continue;
            }

            // Calculate vested amount
            uint256 vested = _calculateVested(schedule);
            uint256 claimable = vested - schedule.claimed;

            if (claimable > 0) {
                // Update state
                schedule.claimed += claimable;
                totalClaimedAmount[schedule.token] += claimable;

                // Transfer tokens
                IERC20(schedule.token).safeTransfer(msg.sender, claimable);

                emit VestedClaimed(
                    vestingId,
                    msg.sender,
                    schedule.token,
                    claimable
                );
            }
        }
    }

    /// @notice Revokes a vesting schedule (owner only, emergency use)
    /// @dev Already vested tokens are still claimable, unvested are returned
    /// @param vestingId The vesting schedule ID
    function revokeVesting(uint256 vestingId) external onlyOwner nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[vestingId];

        if (schedule.beneficiary == address(0)) revert VestingNotFound();
        if (schedule.revoked) revert AlreadyRevoked();

        // Calculate amounts
        uint256 vested = _calculateVested(schedule);
        uint256 unvested = schedule.amount - vested;

        // Mark as revoked
        schedule.revoked = true;

        // Transfer unvested back to owner
        if (unvested > 0) {
            totalVestedAmount[schedule.token] -= unvested;
            IERC20(schedule.token).safeTransfer(owner(), unvested);
        }

        emit VestingRevoked(vestingId, schedule.beneficiary, vested, unvested);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Gets complete vesting schedule information
    /// @param vestingId The vesting schedule ID
    /// @return schedule The vesting schedule struct
    function getVestingInfo(
        uint256 vestingId
    ) external view returns (VestingSchedule memory schedule) {
        return vestingSchedules[vestingId];
    }

    /// @notice Gets all vesting IDs for a user
    /// @param user User address
    /// @return vestingIds Array of vesting IDs
    function getUserVestingIds(
        address user
    ) external view returns (uint256[] memory vestingIds) {
        return userVestingIds[user];
    }

    /// @notice Gets the number of vesting schedules for a user
    /// @param user User address
    /// @return count Number of vesting schedules
    function getUserVestingCount(
        address user
    ) external view returns (uint256 count) {
        return userVestingIds[user].length;
    }

    /// @notice Calculates total vested amount for a schedule
    /// @param vestingId The vesting schedule ID
    /// @return vested Total vested amount
    function getVestedAmount(
        uint256 vestingId
    ) external view returns (uint256 vested) {
        VestingSchedule storage schedule = vestingSchedules[vestingId];
        if (schedule.beneficiary == address(0)) revert VestingNotFound();

        return _calculateVested(schedule);
    }

    /// @notice Calculates claimable amount for a schedule
    /// @param vestingId The vesting schedule ID
    /// @return claimable Amount that can be claimed now
    function getClaimableAmount(
        uint256 vestingId
    ) external view returns (uint256 claimable) {
        VestingSchedule storage schedule = vestingSchedules[vestingId];
        if (schedule.beneficiary == address(0)) revert VestingNotFound();
        if (schedule.revoked) return 0;

        uint256 vested = _calculateVested(schedule);
        return vested - schedule.claimed;
    }

    /// @notice Gets all vesting information for a user
    /// @param user User address
    /// @return schedules Array of vesting schedules
    /// @return claimableAmounts Array of claimable amounts per schedule
    function getUserVestings(
        address user
    )
        external
        view
        returns (
            VestingSchedule[] memory schedules,
            uint256[] memory claimableAmounts
        )
    {
        uint256[] memory vestingIds = userVestingIds[user];
        uint256 length = vestingIds.length;

        schedules = new VestingSchedule[](length);
        claimableAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 vestingId = vestingIds[i];
            VestingSchedule storage schedule = vestingSchedules[vestingId];

            schedules[i] = schedule;

            if (!schedule.revoked) {
                uint256 vested = _calculateVested(schedule);
                claimableAmounts[i] = vested - schedule.claimed;
            }
        }
    }

    /// @notice Gets total claimable amount across all user's vesting schedules
    /// @param user User address
    /// @return totalClaimable Total amount that can be claimed
    function getTotalClaimable(
        address user
    ) external view returns (uint256 totalClaimable) {
        uint256[] memory vestingIds = userVestingIds[user];

        for (uint256 i = 0; i < vestingIds.length; i++) {
            VestingSchedule storage schedule = vestingSchedules[vestingIds[i]];

            if (!schedule.revoked) {
                uint256 vested = _calculateVested(schedule);
                totalClaimable += (vested - schedule.claimed);
            }
        }
    }

    /// @notice Gets contract statistics for a token
    /// @param token Token address
    /// @return totalVested Total amount currently vesting
    /// @return totalClaimed Total amount claimed
    /// @return balance Contract token balance
    function getTokenStats(
        address token
    )
        external
        view
        returns (uint256 totalVested, uint256 totalClaimed, uint256 balance)
    {
        totalVested = totalVestedAmount[token];
        totalClaimed = totalClaimedAmount[token];
        balance = IERC20(token).balanceOf(address(this));
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Calculates the vested amount for a schedule
     * @dev Uses linear vesting formula: vested = (amount * elapsed) / duration
     * @custom:math If vesting hasn't started, returns 0. If complete, returns full amount.
     * @param schedule The vesting schedule
     * @return vested The vested amount
     */
    function _calculateVested(
        VestingSchedule memory schedule
    ) internal view returns (uint256 vested) {
        // If vesting hasn't started, return 0
        if (block.timestamp < schedule.start) {
            return 0;
        }

        // If vesting is complete, return full amount
        if (block.timestamp >= schedule.start + schedule.duration) {
            return schedule.amount;
        }

        // Linear vesting calculation
        uint256 elapsed = block.timestamp - schedule.start;
        vested = (schedule.amount * elapsed) / schedule.duration;
    }
}
