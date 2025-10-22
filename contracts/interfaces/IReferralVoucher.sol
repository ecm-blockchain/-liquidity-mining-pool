// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IReferralVoucher {
    struct VoucherInput {
        bytes32 vid;
        bytes32 codeHash;
        address owner;
        uint16 directBps;
        bool transferOnUse;
        uint64 expiry;
        uint32 maxUses;
        uint256 nonce;
    }

    struct VoucherResult {
        bytes32 codeHash;
        address owner;
        uint16 directBps;
        bool transferOnUse;
        uint32 uses;
    }

    function verifyAndConsume(
        VoucherInput calldata voucher,
        bytes calldata signature,
        address redeemer
    ) external returns (VoucherResult memory result);
}
