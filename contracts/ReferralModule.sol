// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title ReferralModule - Multi-Level Referral System with Direct & Reward-Based Commissions
/// @notice Handles referral tracking, direct commission payments, and off-chain calculated multi-level reward commissions via Merkle proofs
/// @dev Two-tier commission system:
///      1. Direct Commission: Paid immediately when buyer stakes (based on staked amount)
///      2. Multi-Level Reward Commission: Calculated off-chain when rewards claimed, distributed via Merkle claim
contract ReferralModule is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // CONSTANTS
    // ============================================

    uint16 public constant BPS_DENOM = 10000; // 100% = 10000 bps
    uint8 public constant MAX_LEVELS = 10; // Max 10 levels for multi-level

    // ============================================
    // STRUCTS
    // ============================================

    struct ReferralPayoutRoot {
        bytes32 root;
        address token;
        uint256 totalAmount;
        uint256 claimed;
        bool funded;
        uint64 createdAt;
        uint64 expiry;
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    // Pool-level multi-level commission configuration
    mapping(uint256 => uint16[]) public poolLevelConfig; // poolId => [L1_bps, L2_bps, ...]

    // Buyer → Referrer mapping
    mapping(address => address) public referrerOf;

    // Accrued direct commissions
    mapping(address => uint256) public directAccrued;

    // Token address for accrued commissions (referrer => token)
    mapping(address => address) public accruedToken;

    // Merkle roots for reward commission epochs
    mapping(uint256 => ReferralPayoutRoot) public payoutRoots;

    // Tracks if user claimed in a specific epoch
    mapping(uint256 => mapping(address => bool)) public claimedInEpoch;

    // Authorized PoolManager
    address public poolManager;

    // Analytics
    uint256 public totalDirectPaid;
    uint256 public totalMultiLevelPaid;

    // ============================================
    // EVENTS
    // ============================================

    event PoolLevelConfigSet(uint256 indexed poolId, uint16[] mlBps);
    event ReferrerLinked(address indexed buyer, address indexed referrer, bytes32 codeHash);
    event DirectCommissionPaid(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, bytes32 codeHash);
    event DirectCommissionAccrued(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, bytes32 codeHash);
    event DirectAccrualWithdrawn(address indexed referrer, uint256 amount, address indexed to);
    event RewardClaimRecorded(address indexed claimant, uint256 indexed poolId, uint256 rewardAmount, uint256 timestamp);
    event ReferralPayoutRootSubmitted(uint256 indexed epochId, bytes32 indexed root, address token, uint256 totalAmount, uint64 expiry);
    event ReferralPayoutClaimed(uint256 indexed epochId, address indexed claimer, address token, uint256 amount);
    event UnclaimedFundsWithdrawn(uint256 indexed epochId, address indexed to, uint256 amount);
    event PoolManagerSet(address indexed poolManager);

    // ============================================
    // ERRORS
    // ============================================

    error InvalidConfig();
    error InvalidSignature();
    error SelfReferral();
    error ReferrerAlreadySet();
    error UnauthorizedCaller();
    error InsufficientBalance();
    error InvalidAmount();
    error EpochAlreadyExists();
    error EpochNotFound();
    error EpochNotFunded();
    error EpochNotExpired();
    error AlreadyClaimed();
    error InvalidProof();
    error TransferFailed();
    error InvalidAddress();
    error CyclicReferral();

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyPoolManager() {
        if (msg.sender != poolManager && msg.sender != owner()) revert UnauthorizedCaller();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor() Ownable(msg.sender) {}

    // ============================================
    // ADMIN FUNCTIONS - CONFIGURATION
    // ============================================

    /// @notice Sets the PoolManager contract address
    function setPoolManager(address _poolManager) external onlyOwner {
        if (_poolManager == address(0)) revert InvalidAddress();
        poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    /// @notice Sets the multi-level commission configuration for a pool
    /// @param poolId Pool ID
    /// @param mlBps Array of commission percentages per level [L1, L2, ...]
    function setPoolLevelConfig(uint256 poolId, uint16[] calldata mlBps) external onlyOwner {
        if (mlBps.length == 0 || mlBps.length > MAX_LEVELS) revert InvalidConfig();
        uint256 totalMLBps = 0;
        for (uint i = 0; i < mlBps.length; i++) {
            totalMLBps += mlBps[i];
        }
        if (totalMLBps > BPS_DENOM / 2) revert InvalidConfig(); // Max 50%
        delete poolLevelConfig[poolId];
        for (uint i = 0; i < mlBps.length; i++) {
            poolLevelConfig[poolId].push(mlBps[i]);
        }
        emit PoolLevelConfigSet(poolId, mlBps);
    }

    // ============================================
    // INTEGRATION FUNCTIONS - CALLED BY POOLMANAGER
    // ============================================

    /// @notice Records purchase and pays/accrues direct commission (called by PoolManager after voucher verification)
    /// @param codeHash Hash of the referral code
    /// @param buyer Buyer address
    /// @param referrer Referrer address (from voucher)
    /// @param poolId Pool ID
    /// @param stakedAmount Amount of ECM staked
    /// @param token ECM token address
    /// @param directBps Direct commission rate from voucher
    /// @param transferOnUse If true, transfer immediately; else accrue
    /// @return directAmount Amount of direct commission
    function recordPurchaseAndPayDirect(
        bytes32 codeHash,
        address buyer,
        address referrer,
        uint256 poolId,
        uint256 stakedAmount,
        address token,
        uint16 directBps,
        bool transferOnUse
    ) external onlyPoolManager nonReentrant returns (uint256 directAmount) {
        // Validate directBps is not greater than 100%
        if (directBps > BPS_DENOM) revert InvalidConfig();
        
        // Prevent self-referral
        if (buyer == referrer) revert SelfReferral();
        // Prevent cyclic referrals (2-person loop)
        if (referrerOf[referrer] == buyer) revert CyclicReferral();

        // Set referrer relationship (only on first purchase)
        if (referrerOf[buyer] == address(0)) {
            referrerOf[buyer] = referrer;
            emit ReferrerLinked(buyer, referrer, codeHash);
        } else {
            if (referrerOf[buyer] != referrer) revert ReferrerAlreadySet();
        }

        // Calculate direct commission
        directAmount = (stakedAmount * directBps) / BPS_DENOM;
        if (directAmount > 0) {
            if (transferOnUse) {
                uint256 contractBalance = IERC20(token).balanceOf(address(this));
                if (contractBalance < directAmount) revert InsufficientBalance();
                IERC20(token).safeTransfer(referrer, directAmount);
                totalDirectPaid += directAmount;
                emit DirectCommissionPaid(referrer, buyer, poolId, stakedAmount, directAmount, codeHash);
            } else {
                directAccrued[referrer] += directAmount;
                accruedToken[referrer] = token; // Store token address for withdrawal
                emit DirectCommissionAccrued(referrer, buyer, poolId, stakedAmount, directAmount, codeHash);
            }
        }
        return directAmount;
    }

    /// @notice Alternative: Just link referrer (if PoolManager paid direct commission itself)
    /// @param buyer Buyer address
    /// @param referrer Referrer address
    /// @param codeHash Hash of the referral code
    function linkReferrer(
        address buyer,
        address referrer,
        bytes32 codeHash
    ) external onlyPoolManager {
        if (buyer == referrer) revert SelfReferral();
        if (referrerOf[referrer] == buyer) revert CyclicReferral();
        if (referrerOf[buyer] == address(0)) {
            referrerOf[buyer] = referrer;
            emit ReferrerLinked(buyer, referrer, codeHash);
        } else {
            if (referrerOf[buyer] != referrer) revert ReferrerAlreadySet();
        }
    }

    /// @notice Records a reward claim event (for off-chain engine)
    /// @dev Off-chain engine can get tx hash from event receipt; timestamp provides ordering
    function recordRewardClaimEvent(
        address claimant,
        uint256 poolId,
        uint256 rewardAmount
    ) external onlyPoolManager {
        emit RewardClaimRecorded(claimant, poolId, rewardAmount, block.timestamp);
    }

    // ============================================
    // ADMIN FUNCTIONS - MERKLE PAYOUT MANAGEMENT
    // ============================================

    /// @notice Submits a Merkle root for multi-level reward commission epoch
    /// @param epochId Unique epoch identifier
    /// @param token Token address (ECM)
    /// @param totalAmount Total amount to be distributed
    /// @param merkleRoot Merkle root of all payouts
    /// @param expiry Expiration timestamp for claims
    function submitReferralPayoutRoot(
        uint256 epochId,
        address token,
        uint256 totalAmount,
        bytes32 merkleRoot,
        uint64 expiry
    ) external onlyOwner {
        if (payoutRoots[epochId].root != bytes32(0))
            revert EpochAlreadyExists();
        if (token == address(0)) revert InvalidAddress();
        if (totalAmount == 0) revert InvalidAmount();
        if (merkleRoot == bytes32(0)) revert InvalidAmount();

        // Verify contract has sufficient balance
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < totalAmount) revert InsufficientBalance();

        // Store payout root
        ReferralPayoutRoot storage root = payoutRoots[epochId];
        root.root = merkleRoot;
        root.token = token;
        root.totalAmount = totalAmount;
        root.claimed = 0;
        root.funded = true;
        root.createdAt = uint64(block.timestamp);
        root.expiry = expiry;

        emit ReferralPayoutRootSubmitted(
            epochId,
            merkleRoot,
            token,
            totalAmount,
            expiry
        );
    }

    /// @notice Withdraws unclaimed funds after epoch expiry
    /// @param epochId Epoch identifier
    /// @param to Recipient address
    function withdrawUnclaimed(
        uint256 epochId,
        address to
    ) external onlyOwner nonReentrant {
        ReferralPayoutRoot storage root = payoutRoots[epochId];
        if (root.root == bytes32(0)) revert EpochNotFound();
        if (root.expiry == 0 || block.timestamp < root.expiry)
            revert EpochNotExpired();

        uint256 unclaimed = root.totalAmount - root.claimed;
        if (unclaimed == 0) revert InvalidAmount();

        // Mark as fully claimed to prevent re-entry
        root.claimed = root.totalAmount;

        IERC20(root.token).safeTransfer(to, unclaimed);

        emit UnclaimedFundsWithdrawn(epochId, to, unclaimed);
    }

    // ============================================
    // USER FUNCTIONS - CLAIMS
    // ============================================

    /// @notice Claims multi-level reward commission payout using Merkle proof
    /// @param epochId Epoch identifier
    /// @param token Token address (must match epoch)
    /// @param amount Amount to claim
    /// @param proof Merkle proof
    function claimReferral(
        uint256 epochId,
        address token,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        ReferralPayoutRoot storage root = payoutRoots[epochId];

        // Validate epoch
        if (root.root == bytes32(0)) revert EpochNotFound();
        if (!root.funded) revert EpochNotFunded();
        if (root.token != token) revert InvalidAddress();

        // Check if already claimed
        if (claimedInEpoch[epochId][msg.sender]) revert AlreadyClaimed();

        // Verify Merkle proof
        bytes32 leaf = keccak256(
            abi.encodePacked(msg.sender, token, amount, epochId)
        );
        if (!MerkleProof.verify(proof, root.root, leaf)) revert InvalidProof();

        // Mark as claimed
        claimedInEpoch[epochId][msg.sender] = true;
        root.claimed += amount;

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);
        totalMultiLevelPaid += amount;

        emit ReferralPayoutClaimed(epochId, msg.sender, token, amount);
    }

    /// @notice Withdraws accrued direct commissions
    /// @param amount Amount to withdraw (0 = withdraw all)
    function withdrawDirectAccrual(uint256 amount) external nonReentrant {
        uint256 accrued = directAccrued[msg.sender];
        if (accrued == 0) revert InvalidAmount();
        
        uint256 toWithdraw = amount == 0 ? accrued : amount;
        if (toWithdraw > accrued) revert InvalidAmount();
        
        // Get stored token address
        address token = accruedToken[msg.sender];
        if (token == address(0)) revert InvalidAddress();
        
        directAccrued[msg.sender] = accrued - toWithdraw;
        IERC20(token).safeTransfer(msg.sender, toWithdraw);
        emit DirectAccrualWithdrawn(msg.sender, toWithdraw, msg.sender);
    }

    /// @notice Admin withdraws accrued direct commission on behalf of user
    /// @param referrer Referrer address
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function withdrawDirectAccrualFor(
        address referrer,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        uint256 accrued = directAccrued[referrer];
        if (accrued == 0 || amount > accrued) revert InvalidAmount();
        if (to == address(0)) revert InvalidAddress();
        
        // Get stored token address
        address token = accruedToken[referrer];
        if (token == address(0)) revert InvalidAddress();
        
        directAccrued[referrer] = accrued - amount;
        IERC20(token).safeTransfer(to, amount);
        emit DirectAccrualWithdrawn(referrer, amount, to);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Gets referrer for a buyer
    /// @param buyer Buyer address
    /// @return Referrer address
    function getReferrer(address buyer) external view returns (address) {
        return referrerOf[buyer];
    }

    // ...existing code...

    /// @notice Gets payout root information
    /// @param epochId Epoch identifier
    /// @return root Merkle root
    /// @return token Token address
    /// @return totalAmount Total payout amount
    /// @return claimed Amount claimed so far
    /// @return funded Whether epoch is funded
    function getPayoutRootInfo(
        uint256 epochId
    )
        external
        view
        returns (
            bytes32 root,
            address token,
            uint256 totalAmount,
            uint256 claimed,
            bool funded
        )
    {
        ReferralPayoutRoot storage payoutRoot = payoutRoots[epochId];
        return (
            payoutRoot.root,
            payoutRoot.token,
            payoutRoot.totalAmount,
            payoutRoot.claimed,
            payoutRoot.funded
        );
    }

    /// @notice Checks if user has claimed in a specific epoch
    /// @param epochId Epoch identifier
    /// @param user User address
    /// @return Whether user has claimed
    function hasClaimed(
        uint256 epochId,
        address user
    ) external view returns (bool) {
        return claimedInEpoch[epochId][user];
    }

    /// @notice Gets direct accrual balance for a referrer
    /// @param referrer Referrer address
    /// @return Accrued amount
    function getDirectAccrual(
        address referrer
    ) external view returns (uint256) {
        return directAccrued[referrer];
    }

    /// @notice Calculates expected direct commission for a staked amount
    /// @param stakedAmount Staked amount
    /// @param directBps Direct commission rate
    /// @return Expected direct commission
    function calculateDirectCommission(uint256 stakedAmount, uint16 directBps) external pure returns (uint256) {
        return (stakedAmount * directBps) / BPS_DENOM;
    }

    /// @notice Gets pool-level multi-level commission configuration
    /// @param poolId Pool ID
    /// @return mlBps Array of commission percentages per level
    function getPoolLevelConfig(uint256 poolId) external view returns (uint16[] memory mlBps) {
        return poolLevelConfig[poolId];
    }

    /// @notice Gets referral chain for a buyer (for off-chain use)
    function getReferralChain(address buyer, uint8 maxLevels) external view returns (address[] memory chain) {
        chain = new address[](maxLevels);
        address current = referrerOf[buyer];
        uint8 level = 0;
        while (current != address(0) && level < maxLevels) {
            chain[level] = current;
            current = referrerOf[current];
            level++;
        }
        return chain;
    }

    // ============================================
    // ADMIN FUNCTIONS - EMERGENCY
    // ============================================

    /// @notice Emergency token recovery (only for mistakenly sent tokens)
    /// @param token Token address
    /// @param amount Amount to recover
    /// @param to Recipient address
    function emergencyRecoverTokens(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();

        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Fund contract with tokens for direct commissions
    /// @param token Token address
    /// @param amount Amount to fund
    function fundContract(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
