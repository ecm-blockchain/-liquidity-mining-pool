# Off-Chain ECM Reserves Calculation Function

Based on our extensive discussion and analysis of the token flows, here's the correct off-chain implementation of `calculateECMReservesForUnstakes` that works across all pools collectively:

```javascript
/**
 * Calculates ECM reserves needed for unstakes across all pools (off-chain implementation)
 * 
 * IMPORTANT: This function uses the CORRECT accounting logic where:
 * - Staked tokens are already in the contract (they don't need to be "available")
 * - ONLY pending rewards need to be verified as available
 * - Tokens moved to LiquidityManager don't affect availability (they can be refilled)
 * 
 *   - ecmNeeded: Total ECM needed to cover all pending rewards across all pools
 *   - ecmAvailable: ECM available for rewards (contract balance minus staked tokens)
 *   - deficit: ECM shortage (if ecmAvailable < ecmNeeded)
 *   - isSufficient: Whether there's enough ECM for all pending rewards
 */
```

### Reconciles all ECM tokens to ensure proper accounting across all pools
```solidity
    function reconcileAllPools() external view {
        uint256 totalExpected = 0;
        uint256 totalActual = 0;
        for (uint256 poolId = 0; poolId < poolCount; poolId++) {
            Pool storage pool = pools[poolId];
            // Calculate expected balance for this pool
            uint256 expectedBalance = pool.allocatedForSale
                + pool.allocatedForRewards
                - pool.rewardsPaid
                - pool.ecmMovedToLiquidity
                - pool.lifetimeUnstakeVolume
                - pool.totalPenaltiesCollected;
            totalExpected += expectedBalance;
            // Actual balance for this pool's ECM token
        }
        totalActual = pool.ecm.balanceOf(address(this));
        // Verify they match (with small tolerance for rounding)
        require(totalActual >= totalExpected, "Balance mismatch: contract has less than expected");
        require(totalActual <= totalExpected + 1, "Balance mismatch: contract has more than expected");
    }
```

```javascript
/**
 * Calculates ECM reserves needed for unstakes across all pools (off-chain implementation)
 * 
 * @param {Array} pools - Array of pool objects with complete state data
 * @param {BigInt} currentECMBalance - Current ECM balance of the PoolManager contract
 * @returns {Object} Calculation results
 */
function calculateECMReservesForUnstakesOffChain(pools, currentECMBalance) {
  // Calculate total pending rewards across all pools
  let totalPendingRewards = 0n;
  for (const pool of pools) {
    const pendingRewards = BigInt(pool.allocatedForRewards || 0) - BigInt(pool.rewardsPaid || 0);
    totalPendingRewards += pendingRewards;
  }
  
  // Calculate total staked across all pools
  let totalStaked = 0n;
  for (const pool of pools) {
    totalStaked += BigInt(pool.totalStaked || 0);
  }
  
  // Convert currentECMBalance to BigInt if it's not already
  const balance = typeof currentECMBalance === 'bigint' ? 
                 currentECMBalance : BigInt(currentECMBalance);
  
  // Available for rewards = total balance MINUS staked tokens
  const availableForRewards = balance > totalStaked ? 
                            (balance - totalStaked) : 0n;
  
  // Calculate deficit (if any)
  const deficit = totalPendingRewards > availableForRewards ? 
                 (totalPendingRewards - availableForRewards) : 0n;
  
  const isSufficient = deficit === 0n;
  
  return {
    ecmNeeded: totalPendingRewards,
    ecmAvailable: availableForRewards,
    deficit: deficit,
    isSufficient: isSufficient
  };
}
```