// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ReferralVoucher - EIP-712 Voucher Verification for Referral Codes
/// @notice Verifies off-chain generated referral vouchers with EIP-712 signatures
/// @dev Single-use or limited-use vouchers with expiry, revocation, and authorized issuer management
contract ReferralVoucher is Ownable {
    // ============================================
    // CONSTANTS & EIP-712
    // ============================================

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant VOUCHER_TYPEHASH = 
        keccak256("ReferralVoucher(bytes32 vid,bytes32 codeHash,address owner,uint16 directBps,bool transferOnUse,uint64 expiry,uint32 maxUses,uint256 nonce)");

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Voucher input data structure
    struct VoucherInput {
        bytes32 vid;           // Unique voucher ID
        bytes32 codeHash;      // Hash of referral code string
        address owner;         // Referrer who owns this code
        uint16 directBps;      // Direct commission rate (bps)
        bool transferOnUse;    // If true, transfer commission immediately
        uint64 expiry;         // Expiration timestamp (0 = never expires)
        uint32 maxUses;        // Maximum uses (0 = unlimited)
        uint256 nonce;         // Nonce for replay protection
    }

    /// @notice Voucher consumption result
    struct VoucherResult {
        bytes32 codeHash;
        address owner;         // Referrer
        uint16 directBps;
        bool transferOnUse;
        uint32 uses;
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Authorized issuers who can sign vouchers
    mapping(address => bool) public isIssuer;

    /// @notice Tracks usage count per voucher ID
    mapping(bytes32 => uint32) public voucherUses;

    /// @notice Tracks revoked vouchers
    mapping(bytes32 => bool) public voucherRevoked;

    /// @notice Authorized PoolManager contract
    address public poolManager;

    // ============================================
    // EVENTS
    // ============================================

    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);
    event VoucherConsumed(
        bytes32 indexed vid,
        bytes32 indexed codeHash,
        address indexed owner,
        address redeemer,
        uint32 uses
    );
    event VoucherRevokedEvent(bytes32 indexed vid);
    event PoolManagerSet(address indexed poolManager);

    // ============================================
    // ERRORS
    // ============================================

    error InvalidSignature();
    error VoucherExpired();
    error VoucherIsRevoked();
    error MaxUsesReached();
    error UnauthorizedCaller();
    error InvalidAddress();
    error InvalidIssuer();

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
                keccak256(bytes("ReferralVoucher")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /// @notice Sets the PoolManager contract address
    function setPoolManager(address _poolManager) external onlyOwner {
        if (_poolManager == address(0)) revert InvalidAddress();
        poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    /// @notice Adds an authorized issuer
    function addIssuer(address issuer) external onlyOwner {
        if (issuer == address(0)) revert InvalidAddress();
        isIssuer[issuer] = true;
        emit IssuerAdded(issuer);
    }

    /// @notice Removes an authorized issuer
    function removeIssuer(address issuer) external onlyOwner {
        isIssuer[issuer] = false;
        emit IssuerRemoved(issuer);
    }

    /// @notice Revokes a voucher ID
    function revokeVoucher(bytes32 vid) external onlyOwner {
        voucherRevoked[vid] = true;
        emit VoucherRevokedEvent(vid);
    }

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /// @notice Verifies and consumes a voucher (called by PoolManager)
    /// @param voucher Voucher input data
    /// @param signature EIP-712 signature from authorized issuer
    /// @param redeemer Address redeeming the voucher (buyer)
    /// @return result Voucher consumption result
    function verifyAndConsume(
        VoucherInput calldata voucher,
        bytes calldata signature,
        address redeemer
    ) external onlyPoolManager returns (VoucherResult memory result) {
        // Check revocation
        if (voucherRevoked[voucher.vid]) revert VoucherIsRevoked();

        // Check expiry
        if (voucher.expiry > 0 && block.timestamp > voucher.expiry) {
            revert VoucherExpired();
        }

        // Check maxUses
        uint32 currentUses = voucherUses[voucher.vid];
        if (voucher.maxUses > 0 && currentUses >= voucher.maxUses) {
            revert MaxUsesReached();
        }

        // Verify EIP-712 signature
        bytes32 structHash = keccak256(
            abi.encode(
                VOUCHER_TYPEHASH,
                voucher.vid,
                voucher.codeHash,
                voucher.owner,
                voucher.directBps,
                voucher.transferOnUse,
                voucher.expiry,
                voucher.maxUses,
                voucher.nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        address signer = recoverSigner(digest, signature);

        if (!isIssuer[signer]) revert InvalidSignature();

        // Increment usage count
        voucherUses[voucher.vid] = currentUses + 1;

        // Emit event
        emit VoucherConsumed(
            voucher.vid,
            voucher.codeHash,
            voucher.owner,
            redeemer,
            currentUses + 1
        );

        // Return result
        result = VoucherResult({
            codeHash: voucher.codeHash,
            owner: voucher.owner,
            directBps: voucher.directBps,
            transferOnUse: voucher.transferOnUse,
            uses: currentUses + 1
        });
    }

    /// @dev Recovers signer from EIP-712 signature
    function recoverSigner(
        bytes32 digest,
        bytes memory signature
    ) public pure returns (address) {
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

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Gets usage count for a voucher
    function getVoucherUses(bytes32 vid) external view returns (uint32) {
        return voucherUses[vid];
    }

    /// @notice Checks if a voucher is revoked
    function isVoucherRevoked(bytes32 vid) external view returns (bool) {
        return voucherRevoked[vid];
    }
}
