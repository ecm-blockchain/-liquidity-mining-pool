// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title IReferralModule - Interface for ReferralModule contract
/// @notice Defines the integration points between PoolManager and ReferralModule
interface IReferralModule {
    /// @notice Records a purchase and pays/accrues direct commission
    /// @param codeHash Hash of the referral code used
    /// @param buyer Address of the buyer
    /// @param poolId Pool ID from PoolManager
    /// @param stakedAmount Amount of ECM staked
    /// @param token ECM token address
    /// @return referrer Address of the referrer
    /// @return directAmount Amount of direct commission
    function recordPurchaseAndPayDirect(
        bytes32 codeHash,
        address buyer,
        uint256 poolId,
        uint256 stakedAmount,
        address token
    ) external returns (address referrer, uint256 directAmount);

    /// @notice Records a reward claim event (for off-chain engine)
    /// @param claimant Address claiming rewards
    /// @param poolId Pool ID
    /// @param rewardAmount Amount of rewards claimed
    /// @param claimTxHash Transaction hash of the claim
    function recordRewardClaimEvent(
        address claimant,
        uint256 poolId,
        uint256 rewardAmount,
        bytes32 claimTxHash
    ) external;

    /// @notice Gets referrer for a buyer
    /// @param buyer Buyer address
    /// @return Referrer address
    function getReferrer(address buyer) external view returns (address);

    /// @notice Calculates expected direct commission for a staked amount
    /// @param codeHash Referral code hash
    /// @param stakedAmount Amount being staked
    /// @return expectedCommission Expected direct commission
    function calculateDirectCommission(
        bytes32 codeHash,
        uint256 stakedAmount
    ) external view returns (uint256 expectedCommission);
}
