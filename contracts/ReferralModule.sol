// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title ReferralModule - Multi-Level Referral System with Direct & Reward-Based Commissions
/// @notice Handles referral code registration, direct commission payments, and off-chain calculated multi-level reward commissions via Merkle proofs
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

    // Global commission configuration
    uint8 public commissionLevels;
    uint16[] public commissionBps; // [L1, L2, ...]
    uint16 public directBps; // Direct commission (for staked amount)
    bool public transferOnUse; // If true, transfer direct commission immediately; else accrue

    // EIP-712 domain separator
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant VOUCHER_TYPEHASH = keccak256("ReferralVoucher(string code,address referrer,uint256 nonce)");
    mapping(address => uint256) public nonces; // Nonce per user for replay protection

    // Buyer → Referrer mapping
    mapping(address => address) public referrerOf;

    // Accrued direct commissions
    mapping(address => uint256) public directAccrued;

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

    event CommissionConfigUpdated(uint8 levels, uint16[] bps, uint16 directBps, bool transferOnUse);
    event ReferrerLinked(address indexed buyer, address indexed referrer, string code);
    event DirectCommissionPaid(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, string code);
    event DirectCommissionAccrued(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, string code);
    event DirectAccrualWithdrawn(address indexed referrer, uint256 amount, address indexed to);
    event RewardClaimRecorded(address indexed claimant, uint256 indexed poolId, uint256 rewardAmount, bytes32 indexed claimTxHash);
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
        if (msg.sender != poolManager) revert UnauthorizedCaller();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor() Ownable(msg.sender) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ReferralModule")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // ============================================
    // ADMIN FUNCTIONS - CONFIGURATION
    // ============================================

    /// @notice Sets the PoolManager contract address
    function setPoolManager(address _poolManager) external onlyOwner {
        if (_poolManager == address(0)) revert InvalidAddress();
        poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    /// @notice Sets the global commission configuration
    function setCommissionConfig(uint8 levels, uint16[] calldata bps, uint16 _directBps, bool _transferOnUse) external onlyOwner {
        if (levels == 0 || levels > MAX_LEVELS) revert InvalidConfig();
        if (bps.length != levels) revert InvalidConfig();
        uint256 totalMLBps = 0;
        for (uint i = 0; i < bps.length; i++) {
            totalMLBps += bps[i];
        }
        if (totalMLBps > BPS_DENOM / 2) revert InvalidConfig(); // Max 50%
        if (_directBps > BPS_DENOM / 5) revert InvalidConfig(); // Max 20%
        commissionLevels = levels;
        delete commissionBps;
        for (uint i = 0; i < bps.length; i++) {
            commissionBps.push(bps[i]);
        }
        directBps = _directBps;
        transferOnUse = _transferOnUse;
        emit CommissionConfigUpdated(levels, bps, _directBps, _transferOnUse);
    }

    // ============================================
    // INTEGRATION FUNCTIONS - CALLED BY POOLMANAGER
    // ============================================

    /// @notice Uses an EIP-712 signed voucher to link buyer to referrer and pay/accrue direct commission
    /// @param code Referral code string
    /// @param referrer Referrer address
    /// @param poolId Pool ID
    /// @param stakedAmount Amount of ECM staked
    /// @param token ECM token address
    /// @param signature EIP-712 signature from authorized issuer
    function useReferralVoucher(
        string calldata code,
        address referrer,
        uint256 poolId,
        uint256 stakedAmount,
        address token,
        bytes calldata signature
    ) external onlyPoolManager nonReentrant returns (address, uint256) {
        // EIP-712 verification
        uint256 nonce = nonces[msg.sender];
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, keccak256(bytes(code)), referrer, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = recoverSigner(digest, signature);
        if (signer != owner()) revert InvalidSignature();

        // Prevent self-referral
        if (msg.sender == referrer) revert SelfReferral();
        // Prevent cyclic referrals (2-person loop)
        if (referrerOf[referrer] == msg.sender) revert CyclicReferral();

        // Set referrer relationship (only on first purchase)
        if (referrerOf[msg.sender] == address(0)) {
            referrerOf[msg.sender] = referrer;
            emit ReferrerLinked(msg.sender, referrer, code);
        } else {
            if (referrerOf[msg.sender] != referrer) revert ReferrerAlreadySet();
        }

        nonces[msg.sender]++;

        // Calculate direct commission
        uint256 directAmount = (stakedAmount * directBps) / BPS_DENOM;
        if (directAmount > 0) {
            if (transferOnUse) {
                uint256 contractBalance = IERC20(token).balanceOf(address(this));
                if (contractBalance < directAmount) revert InsufficientBalance();
                IERC20(token).safeTransfer(referrer, directAmount);
                totalDirectPaid += directAmount;
                emit DirectCommissionPaid(referrer, msg.sender, poolId, stakedAmount, directAmount, code);
            } else {
                directAccrued[referrer] += directAmount;
                emit DirectCommissionAccrued(referrer, msg.sender, poolId, stakedAmount, directAmount, code);
            }
        }
        return (referrer, directAmount);
    }

    /// @dev Recovers signer from EIP-712 signature
    function recoverSigner(bytes32 digest, bytes memory signature) public pure returns (address) {
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }

    /// @notice Records a reward claim event (for off-chain engine)
    function recordRewardClaimEvent(
        address claimant,
        uint256 poolId,
        uint256 rewardAmount,
        bytes32 claimTxHash
    ) external onlyPoolManager {
        emit RewardClaimRecorded(claimant, poolId, rewardAmount, claimTxHash);
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
    function claimPayout(
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
        directAccrued[msg.sender] = accrued - toWithdraw;
        // Transfer tokens from contract balance
        IERC20 payoutToken = IERC20(address(0));
        for (uint256 i = 0; i < 256; i++) {
            if (payoutRoots[i].funded && payoutRoots[i].token != address(0)) {
                payoutToken = IERC20(payoutRoots[i].token);
                break;
            }
        }
        require(address(payoutToken) != address(0), "No payout token set");
        payoutToken.safeTransfer(msg.sender, toWithdraw);
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
        directAccrued[referrer] = accrued - amount;
        IERC20 payoutToken = IERC20(address(0));
        for (uint256 i = 0; i < 256; i++) {
            if (payoutRoots[i].funded && payoutRoots[i].token != address(0)) {
                payoutToken = IERC20(payoutRoots[i].token);
                break;
            }
        }
        require(address(payoutToken) != address(0), "No payout token set");
        payoutToken.safeTransfer(to, amount);
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
    function calculateDirectCommission(uint256 stakedAmount) external view returns (uint256) {
        return (stakedAmount * directBps) / BPS_DENOM;
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
