// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IReferralVoucher} from "./IReferralVoucher.sol";

/// @title IReferralModule - Interface for ReferralModule contract
/// @notice Defines the integration points between PoolManager and ReferralModule
interface IReferralModule {
    /// @notice Records a purchase and pays/accrues direct commission
    /// @param codeHash Hash of the referral code used
    /// @param buyer Address of the buyer
    /// @param referrer Address of the referrer (from voucher)
    /// @param poolId Pool ID from PoolManager
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
    ) external returns (uint256 directAmount);

    /// @notice Alternative: Just link referrer (if PoolManager paid direct commission itself)
    /// @param buyer Buyer address
    /// @param referrer Referrer address
    /// @param codeHash Hash of the referral code
    function linkReferrer(
        address buyer,
        address referrer,
        bytes32 codeHash
    ) external;

    /// @notice Records a reward claim event (for off-chain engine)
    /// @param claimant Address claiming rewards
    /// @param poolId Pool ID
    /// @param rewardAmount Amount of rewards claimed
    /// @dev Transaction hash can be obtained from event receipt by off-chain engine
    function recordRewardClaimEvent(
        address claimant,
        uint256 poolId,
        uint256 rewardAmount
    ) external;

    /// @notice Gets referrer for a buyer
    /// @param buyer Buyer address
    /// @return Referrer address
    function getReferrer(address buyer) external view returns (address);

    /// @notice Allows user to set their referrer after initial purchase (one-time only)
    /// @param voucherInput Referral voucher data
    /// @param voucherSignature EIP-712 signature for voucher
    function setMyReferrer(
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) external;

    /// @notice Allows PoolManager to set user's referrer after initial purchase (delegated call)
    /// @param user User address who wants to set referrer
    /// @param voucherInput Referral voucher data
    /// @param voucherSignature EIP-712 signature for voucher
    function setMyReferrerFor(
        address user,
        IReferralVoucher.VoucherInput calldata voucherInput,
        bytes calldata voucherSignature
    ) external;

    /// @notice Calculates expected direct commission for a staked amount
    /// @param stakedAmount Amount being staked
    /// @param directBps Direct commission rate
    /// @return Expected direct commission
    function calculateDirectCommission(
        uint256 stakedAmount,
        uint16 directBps
    ) external pure returns (uint256);
}
