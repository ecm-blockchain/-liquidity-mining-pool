# ReferralModule Implementation Guide

## Overview

The **ReferralModule** is an independent smart contract that manages a two-tier referral commission system for the ECM PoolManager ecosystem:

1. **Direct Commission**: Instant commission paid when a buyer stakes ECM using a referral voucher (based on staked amount)
2. **Multi-Level Reward Commission**: Off-chain calculated commissions paid when buyers claim rewards (based on reward amount, distributed via Merkle proofs)

**Key Integration**: Works with ReferralVoucher contract for EIP-712 signed vouchers instead of on-chain stored codes. Pool-level configuration allows different commission structures per pool.

## Architecture

### Contract Structure
```
ReferralModule (Independent Contract)
├── Pool-Level Commission Configuration
│   ├── Set multi-level rates per pool [L1, L2, L3...]
│   ├── Max 10 levels, total ≤50%
│   └── Configurable by pool admin
├── Direct Commission System
│   ├── Calculate commission on stake (from voucher)
│   ├── Transfer immediately OR accrue
│   └── Track buyer→referrer relationships
└── Multi-Level Reward System
    ├── Emit events for off-chain engine
    ├── Accept funded Merkle roots
    └── Allow claims with proof verification
```

### Integration with PoolManager
```
User → PoolManager.buyAndStake(poolId, maxUsdt, duration, voucherInput)
       ↓
       PoolManager verifies ReferralVoucher signature (EIP-712)
       ↓
       PoolManager calculates ECM, receives USDT, auto-stakes
       ↓
       PoolManager.recordReferral(codeHash, buyer, referrer, poolId, stakedAmount, directBps, transferOnUse)
       ↓
       ReferralModule.recordPurchaseAndPayDirect()
       ├── Validates input params
       ├── Links buyer→referrer (once)
       ├── Calculates directAmount = stakedAmount * directBps / 10000
       ├── Transfers OR accrues commission
       └── Returns directAmount
```

## Key Features

### 1. Pool-Level Commission Configuration
- **Pool-based setup**: Each pool can have different multi-level commission rates
- **Max levels**: Up to 10 levels supported (configurable per pool)
- **Rate limits**: Total multi-level commission ≤50% (5000 bps)
- **Dynamic configuration**: Admin can update rates per pool
- **No per-code storage**: Uses EIP-712 vouchers instead of on-chain code storage

### 2. EIP-712 Voucher Integration  
- **Stateless codes**: Referral codes stored in signed vouchers, not on-chain
- **Signature verification**: PoolManager verifies voucher before calling ReferralModule
- **Commission rates**: Direct commission rate comes from voucher
- **Transfer mode**: Voucher specifies immediate transfer vs accrual
- **Gas efficiency**: No on-chain code lookups required

### 3. Anti-Fraud Security
- **Self-referral prevention**: Buyer cannot be their own referrer
- **Cyclic prevention**: Prevents 2-person referral loops
- **Immutable relationships**: `referrerOf[buyer]` set once, permanent
- **Address validation**: Prevents zero address assignments
- **Access control**: Only PoolManager (or owner) can record purchases

### 4. Direct Commission Flow
```solidity
// Option A: Immediate Transfer (transferOnUse = true)
1. User stakes 1000 ECM with voucher (directBps = 1000)
2. ReferralModule calculates: 1000 * 1000 bps / 10000 = 100 ECM
3. ReferralModule transfers 100 ECM to referrer instantly
4. Emits DirectCommissionPaid event

// Option B: Accrual (transferOnUse = false)
1. User stakes 1000 ECM with voucher (directBps = 1000)
2. ReferralModule calculates: 100 ECM commission
3. directAccrued[referrer] += 100 ECM
4. accruedToken[referrer] = ECM token address
5. Emits DirectCommissionAccrued event
6. Referrer withdraws later via withdrawDirectAccrual()
```

### 5. Post-Purchase Referrer Setting (New Feature)
- **Late referrer assignment**: Users can add referrer codes after their initial purchase/stake
- **One-time only**: Once set, referrer relationship cannot be changed  
- **No retroactive commissions**: Only affects future reward claims, not past staking activity
- **Multiple access patterns**: Direct call to ReferralModule OR delegated via PoolManager
- **Voucher validation**: Uses same EIP-712 voucher system as purchase-time referrals
- **Anti-fraud protection**: Same security as purchase-time (no self-referral, no cycles)

```solidity
// Option A: Direct call to ReferralModule
user.call(ReferralModule.setMyReferrer(voucherInput, signature))

// Option B: Delegated call via PoolManager  
user.call(PoolManager.setMyReferrer(voucherInput, signature))
  ↓ (internally calls)
ReferralModule.setMyReferrerFor(user, voucherInput, signature)
```

**Requirements for setMyReferrer**:
- User must not have existing referrer: `referrerOf[user] == address(0)`
- Valid voucher signature and not expired/revoked
- Referrer cannot be user (no self-referral)
- No referral cycles: `referrerOf[referrer] != user`

### 6. Multi-Level Reward Commission Flow
```
Off-Chain Engine Process:
1. Listen to RewardClaimRecorded events
2. Query referrerOf[buyer] chain: L1, L2, L3, ...
3. Get pool's mlBps configuration: getPoolLevelConfig(poolId)
4. Calculate commissions:
   - L1: rewardAmount * mlBps[0] / 10000
   - L2: rewardAmount * mlBps[1] / 10000
   - L3: rewardAmount * mlBps[2] / 10000
5. Aggregate all commissions into epoch (e.g., weekly batch)
6. Build Merkle tree: leaves = keccak256(beneficiary, token, amount, epochId)
7. Fund contract with totalAmount
8. Submit root: submitReferralPayoutRoot(epochId, token, totalAmount, root, expiry)

On-Chain Claim Process:
1. User fetches proof from off-chain API
2. User calls claimReferral(epochId, token, amount, proof)
3. ReferralModule verifies Merkle proof
4. Transfers tokens to user
5. Marks epoch claim as used
```

## Smart Contract API

### Admin Functions

#### `setPoolManager(address _poolManager)`
- Sets the authorized PoolManager address
- Only PoolManager can call integration functions
- Emits `PoolManagerSet` event

#### `setPoolLevelConfig(uint256 poolId, uint16[] calldata mlBps)`
```solidity
function setPoolLevelConfig(
    uint256 poolId,           // Pool ID to configure
    uint16[] calldata mlBps   // Multi-level rates [L1, L2, L3...] in bps
) external onlyOwner
```

**Constraints**:
- `mlBps.length` ≤ 10 levels (MAX_LEVELS)
- `sum(mlBps)` ≤ 5000 (50%)
- Emits `PoolLevelConfigSet` event

#### `submitReferralPayoutRoot(...)`
```solidity
function submitReferralPayoutRoot(
    uint256 epochId,
    address token,
    uint256 totalAmount,
    bytes32 merkleRoot,
    uint64 expiry
) external onlyOwner
```
Submits a Merkle root for batch reward commission payouts.
**Requirements**:
- Contract must have `totalAmount` of `token` balance
- EpochId must be unique
- MerkleRoot cannot be zero

#### `withdrawUnclaimed(uint256 epochId, address to)`
Withdraws unclaimed funds after epoch expiry (admin only)

#### `fundContract(address token, uint256 amount)`
Funds contract for direct commission transfers

#### `emergencyRecoverTokens(address token, uint256 amount, address to)`
Emergency token recovery for mistakenly sent tokens

### Integration Functions (Called by PoolManager)

#### `recordPurchaseAndPayDirect(...)`
```solidity
function recordPurchaseAndPayDirect(
    bytes32 codeHash,        // Hash of referral code from voucher
    address buyer,           // Buyer address
    address referrer,        // Referrer address from voucher
    uint256 poolId,          // Pool ID
    uint256 stakedAmount,    // Amount of ECM staked
    address token,           // ECM token address
    uint16 directBps,        // Direct commission rate from voucher
    bool transferOnUse       // Transfer mode from voucher
) external onlyPoolManager returns (uint256 directAmount)
```
**Process**:
1. Validates directBps ≤ 10000 (100%)
2. Prevents self-referral and cycles
3. Sets `referrerOf[buyer] = referrer` (once)
4. Calculates `directAmount = stakedAmount * directBps / 10000`
5. Transfers OR accrues commission based on transferOnUse
6. Returns directAmount for PoolManager logging

#### `linkReferrer(address buyer, address referrer, bytes32 codeHash)`
Alternative function to just establish referrer link without paying commission
(useful if PoolManager handles direct commission payments itself)

#### `recordRewardClaimEvent(...)`
```solidity
function recordRewardClaimEvent(
    address claimant,
    uint256 poolId,
    uint256 rewardAmount
) external onlyPoolManager
```
Emits `RewardClaimRecorded` event for off-chain engine to process.
Uses `block.timestamp` for ordering.

#### `setMyReferrerFor(address user, VoucherInput voucher, bytes signature)` 
```solidity
function setMyReferrerFor(
    address user,                    // User to set referrer for
    VoucherInput calldata voucher,   // EIP-712 voucher structure  
    bytes calldata signature         // Voucher signature
) external onlyPoolManager
```
**Process**:
1. Validates user has no existing referrer: `referrerOf[user] == address(0)`
2. Verifies voucher signature via ReferralVoucher.verifyAndConsume()
3. Extracts referrer from voucher.owner
4. Validates anti-fraud rules (no self-referral, no cycles)
5. Sets `referrerOf[user] = referrer`
6. Emits `ReferrerLinked(user, referrer, voucher.codeHash)`

**Note**: Called by PoolManager.setMyReferrer() for delegation pattern

### User Functions

#### `setMyReferrer(VoucherInput voucher, bytes signature)`
```solidity
function setMyReferrer(
    VoucherInput calldata voucher,   // EIP-712 voucher structure
    bytes calldata signature         // Voucher signature  
) external nonReentrant
```
**Direct user function** for setting referrer after initial purchase.
Same validation logic as `setMyReferrerFor` but uses `msg.sender` as user.

**Requirements**:
- User must not have existing referrer
- Valid voucher (not expired, not revoked, within usage limits)
- Referrer must be voucher.owner
- No self-referral: `msg.sender != voucher.owner`
- No cycles: `referrerOf[voucher.owner] != msg.sender`

#### `claimReferral(...)`
```solidity
function claimReferral(
    uint256 epochId,
    address token,
    uint256 amount,
    bytes32[] calldata proof
) external nonReentrant
```
Claims multi-level reward commission using Merkle proof.

**Verification**:
- Epoch exists and is funded
- User hasn't claimed in this epoch
- Token matches epoch token
- Merkle proof valid for `keccak256(abi.encodePacked(user, token, amount, epochId))`

#### `withdrawDirectAccrual(uint256 amount)`
Withdraws accrued direct commissions (for `transferOnUse = false` mode).
Pass `amount = 0` to withdraw all. Uses stored `accruedToken[msg.sender]` address.

#### `withdrawDirectAccrualFor(address referrer, uint256 amount, address to)`
Admin function to withdraw accrued commissions on behalf of referrer.

### View Functions

#### `getReferrer(address buyer) → address`
Returns the referrer for a buyer (or address(0) if none)

#### `getPoolLevelConfig(uint256 poolId) → uint16[] memory`
Returns multi-level commission configuration for a pool

#### `getPayoutRootInfo(uint256 epochId) → (...)`
Returns Merkle root information:
- `root`: Merkle root hash
- `token`: Token address
- `totalAmount`: Total payout amount
- `claimed`: Amount claimed so far
- `funded`: Whether epoch is funded

#### `hasClaimed(uint256 epochId, address user) → bool`
Checks if user has claimed in a specific epoch

#### `getDirectAccrual(address referrer) → uint256`
Returns accrued direct commission balance

#### `calculateDirectCommission(uint256 stakedAmount, uint16 directBps) → uint256`
Calculates expected direct commission (off-chain preview)

#### `getReferralChain(address buyer, uint8 maxLevels) → address[]`
Returns referral chain [L1, L2, L3, ...] for a buyer

#### Analytics Functions
- `totalDirectPaid`: Total direct commissions paid
- `totalMultiLevelPaid`: Total multi-level commissions paid
- `directAccrued[referrer]`: Accrued balance per referrer
- `accruedToken[referrer]`: Token address for accrued balance

## Commission Calculation Rules

### Direct Commission (Staked Amount Based)
```solidity
directAmount = floor(stakedAmount * directBps / 10000)
```
**Example**: 
- Staked: 1000 ECM
- directBps: 1000 (10%) - from voucher
- Commission: 1000 * 1000 / 10000 = 100 ECM

### Multi-Level Reward Commission (Reward Amount Based)
```solidity
// Off-chain calculation per level using pool configuration
poolConfig = getPoolLevelConfig(poolId) // e.g., [500, 300, 200]
level1Commission = floor(rewardAmount * poolConfig[0] / 10000)
level2Commission = floor(rewardAmount * poolConfig[1] / 10000)
level3Commission = floor(rewardAmount * poolConfig[2] / 10000)
```

**Example**:
- Reward claimed: 500 ECM
- Pool mlBps: [500, 300, 200] = [5%, 3%, 2%]
- L1 commission: 500 * 500 / 10000 = 25 ECM
- L2 commission: 500 * 300 / 10000 = 15 ECM
- L3 commission: 500 * 200 / 10000 = 10 ECM

**Rounding**: Uses floor division (integer math). Total funded amount must equal sum of all beneficiary amounts.

## Events

### Pool Configuration
```solidity
event PoolLevelConfigSet(uint256 indexed poolId, uint16[] mlBps);
event PoolManagerSet(address indexed poolManager);
```

### Referrer Relationships
```solidity
event ReferrerLinked(address indexed buyer, address indexed referrer, bytes32 codeHash);
```

### Direct Commissions
```solidity
event DirectCommissionPaid(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, bytes32 codeHash);
event DirectCommissionAccrued(address indexed referrer, address indexed buyer, uint256 indexed poolId, uint256 stakedAmount, uint256 amount, bytes32 codeHash);
event DirectAccrualWithdrawn(address indexed referrer, uint256 amount, address indexed to);
```

### Reward Commissions
```solidity
event RewardClaimRecorded(address indexed claimant, uint256 indexed poolId, uint256 rewardAmount, uint256 timestamp);
event ReferralPayoutRootSubmitted(uint256 indexed epochId, bytes32 indexed root, address token, uint256 totalAmount, uint64 expiry);
event ReferralPayoutClaimed(uint256 indexed epochId, address indexed claimer, address token, uint256 amount);
event UnclaimedFundsWithdrawn(uint256 indexed epochId, address indexed to, uint256 amount);
```

## Off-Chain Engine Requirements

### Responsibilities
1. **Event Monitoring**: Subscribe to `RewardClaimRecorded` events from ReferralModule
2. **Graph Maintenance**: Build and maintain buyer→referrer relationship graph
3. **Pool Configuration**: Track pool-level multi-level commission rates via `PoolLevelConfigSet` events
4. **Commission Calculation**: 
   - For each claim, traverse referral chain
   - Get pool's mlBps configuration: `getPoolLevelConfig(poolId)`
   - Calculate per-level commissions using pool's configuration
   - Skip levels with no referrer (address(0))
5. **Epoch Aggregation**: 
   - Batch commissions into epochs (daily/weekly)
   - Sum per-beneficiary amounts
6. **Merkle Tree Generation**:
   - Leaf format: `keccak256(abi.encodePacked(beneficiary, token, amount, epochId))`
   - Sort leaves before building tree
7. **Funding & Submission**:
   - Transfer `totalAmount` to ReferralModule
   - Call `submitReferralPayoutRoot()`
8. **Proof API**: Serve Merkle proofs via REST API for users to claim

### Database Schema (Recommended)
```sql
-- Pool configurations
CREATE TABLE pool_configs (
    pool_id UINT256 PRIMARY KEY,
    ml_bps UINT16[],
    updated_at TIMESTAMP
);

-- Referrer relationships
CREATE TABLE referrer_links (
    buyer ADDRESS PRIMARY KEY,
    referrer ADDRESS,
    code_hash BYTES32,
    linked_at TIMESTAMP
);

-- Purchase tracking
CREATE TABLE purchases (
    tx_hash BYTES32 PRIMARY KEY,
    buyer ADDRESS,
    referrer ADDRESS,
    pool_id UINT256,
    staked_amount UINT256,
    direct_bps UINT16,
    direct_amount UINT256,
    transfer_on_use BOOLEAN,
    code_hash BYTES32,
    timestamp TIMESTAMP
);

-- Direct commissions
CREATE TABLE direct_commissions (
    id SERIAL PRIMARY KEY,
    referrer ADDRESS,
    buyer ADDRESS,
    pool_id UINT256,
    amount UINT256,
    paid BOOLEAN,
    accrued BOOLEAN,
    paid_tx BYTES32,
    timestamp TIMESTAMP
);

-- Reward claims
CREATE TABLE reward_claims (
    claim_tx BYTES32 PRIMARY KEY,
    claimant ADDRESS,
    pool_id UINT256,
    reward_amount UINT256,
    timestamp UINT256 -- block.timestamp from event
);

-- Multi-level commissions (calculated)
CREATE TABLE ml_commissions (
    id SERIAL PRIMARY KEY,
    epoch_id UINT256,
    pool_id UINT256,
    source_claim_tx BYTES32,
    level UINT8,
    beneficiary ADDRESS,
    amount UINT256,
    FOREIGN KEY (source_claim_tx) REFERENCES reward_claims(claim_tx)
);

-- Payout epochs
CREATE TABLE payout_epochs (
    epoch_id UINT256 PRIMARY KEY,
    token ADDRESS,
    total_amount UINT256,
    merkle_root BYTES32,
    submitted_tx BYTES32,
    funded BOOLEAN,
    expiry UINT64,
    created_at UINT64
);

-- Claims tracking
CREATE TABLE payout_claims (
    id SERIAL PRIMARY KEY,
    epoch_id UINT256,
    beneficiary ADDRESS,
    amount UINT256,
    proof JSONB,
    claimed_tx BYTES32,
    claimed_at TIMESTAMP,
    UNIQUE(epoch_id, beneficiary)
);
```

### API Endpoints (Recommended)
```
GET  /api/v1/proofs/{epochId}/{beneficiary}
     → { epochId, beneficiary, amount, proof: [...], token }

GET  /api/v1/epochs
     → { epochs: [{ epochId, totalAmount, claimed, expiry, ... }] }

GET  /api/v1/referrer/{address}/stats
     → { totalDirectEarned, totalMLEarned, pendingClaims: [...], accruedBalance }

GET  /api/v1/buyer/{address}/chain
     → { chain: [L1, L2, L3, ...] }

GET  /api/v1/pool/{poolId}/config
     → { poolId, mlBps: [L1, L2, L3, ...] }

POST /api/v1/calculate-commission
     Body: { rewardAmount, buyerAddress, poolId }
     → { levels: [{ level, beneficiary, amount }, ...] }
```

## Integration with PoolManager

### Required Changes to PoolManager

#### 1. Add ReferralModule State Variable
```solidity
IReferralModule public referralModule;

function setReferralModule(address _referralModule) external onlyOwner {
    referralModule = IReferralModule(_referralModule);
}
```

#### 2. Modify buyAndStake to Accept Referral Voucher
```solidity
function buyAndStake(
    uint256 poolId,
    uint256 maxUsdtAmount,
    uint256 selectedStakeDuration,
    IReferralVoucher.VoucherInput calldata voucherInput  // NEW PARAMETER
) external nonReentrant whenNotPaused {
    // ... existing validation ...

    // Verify referral voucher (if provided)
    address referrer = address(0);
    uint16 directBps = 0;
    bool transferOnUse = false;
    bytes32 codeHash = bytes32(0);
    
    if (voucherInput.voucher.vid != 0) {
        // Verify EIP-712 signature
        (referrer, directBps, transferOnUse, codeHash) = referralVoucher.verifyAndUse(
            voucherInput.voucher,
            voucherInput.signature
        );
    }

    // ... existing buy logic: calculate ECM, transfer USDT, update accounting ...

    // BEFORE auto-staking, record referral (if voucher was used)
    if (address(referralModule) != address(0) && referrer != address(0)) {
        uint256 directAmount = referralModule.recordPurchaseAndPayDirect(
            codeHash,
            msg.sender,
            referrer,
            poolId,
            ecmToAllocate,
            address(pool.ecm),
            directBps,
            transferOnUse
        );
        // Optional: emit event with referrer info
    }

    // ... continue with auto-stake logic ...
}
```

#### 3. Emit Reward Claim Events
```solidity
function unstake(uint256 poolId) external nonReentrant {
    // ... existing unstake logic ...

    // After claiming rewards, record event
    if (address(referralModule) != address(0) && pending > 0) {
        referralModule.recordRewardClaimEvent(
            msg.sender,
            poolId,
            pending
        );
    }
}

function claimRewards(uint256 poolId) external nonReentrant {
    // ... existing claim logic ...

    // After claiming, record event
    if (address(referralModule) != address(0) && pending > 0) {
        referralModule.recordRewardClaimEvent(
            msg.sender,
            poolId,
            pending
        );
    }
}
```

### Funding Strategies

#### Option A: Pre-fund ReferralModule (Recommended)
```solidity
// Admin funds ReferralModule with ECM tokens for direct commissions
// ReferralModule transfers directly to referrers
ECM.approve(referralModule, 100000e18);
ReferralModule.fundContract(ECMAddress, 100000e18);
```

#### Option B: PoolManager Transfers to Referrer
```solidity
// PoolManager calculates commission and transfers from its balance
(address referrer, uint256 directAmount) = referralModule.recordPurchaseAndPayDirect(...);
if (directAmount > 0) {
    pool.ecm.safeTransfer(referrer, directAmount);
}
```

#### Option C: Accrual Mode with Batch Payouts
```solidity
// Use transferOnUse = false
// Periodically admin batch-pays accrued commissions
for (referrer in referrers) {
    uint256 accrued = referralModule.getDirectAccrual(referrer);
    if (accrued > 0) {
        ECM.transfer(referrer, accrued);
        referralModule.withdrawDirectAccrualFor(referrer, accrued, referrer);
    }
}
```

## Security Considerations

### On-Chain Security
1. **Self-Referral Prevention**: Enforced at contract level
2. **Cyclic Prevention**: Checks for 2-person loops
3. **Immutable Relationships**: `referrerOf` set once, prevents gaming
4. **Reentrancy Protection**: All state-changing functions use `nonReentrant`
5. **Access Control**: `onlyOwner` for admin, `onlyPoolManager` for integration
6. **Merkle Proof Verification**: Prevents unauthorized claims
7. **Double Claim Prevention**: `claimedInEpoch` mapping tracks claims
8. **Funding Verification**: `submitReferralPayoutRoot` checks contract balance

### Off-Chain Security
1. **Event Monitoring**: Must be fault-tolerant, handle chain reorgs
2. **Commission Calculation**: Must use exact same rounding as Solidity
3. **Merkle Tree**: Must be deterministic, reproducible
4. **API Security**: Rate limiting, authentication for proof endpoints
5. **Database Integrity**: Foreign keys, transaction consistency
6. **Audit Trail**: Log all calculations for dispute resolution

### Anti-Sybil Measures
1. **KYC Integration**: Off-chain verification before code issuance
2. **Usage Limits**: `maxUses` per code
3. **Time Limits**: `expiry` timestamps
4. **Rate Limiting**: Admin monitors unusual patterns
5. **Referrer Caps**: Optional per-referrer earning limits (off-chain)

## Testing Checklist

### Test Suite Status: ✅ All Tests Passing
- **Referral Module Tests**: Part of 403 total tests across 8 files
- **Stress Tests**: 19/19 comprehensive stress tests include referral scenarios
- **Integration Tests**: Full end-to-end referral flow validation

### Unit Tests
- ✅ Register referral code with valid params
- ✅ Reject invalid commission rates (> max)
- ✅ Reject self-referral
- ✅ Prevent cyclic referrals
- ✅ Direct commission transfer mode
- ✅ Direct commission accrual mode
- ✅ Merkle proof verification (valid)
- ✅ Merkle proof verification (invalid)
- ✅ Double claim prevention
- ✅ Epoch expiry and withdrawal

### Integration Tests
- ✅ Full flow: buyAndStake with referral code
- ✅ Direct commission paid to referrer
- ✅ Reward claim event emission
- ✅ Multi-level commission calculation (off-chain sim)
- ✅ Merkle root submission and claims
- ✅ Contract funding and balance tracking

### Security Tests
- ✅ Self-referral attempt (should revert)
- ✅ Cyclic referral attempt (should revert)
- ✅ Forge Merkle proof (should revert)
- ✅ Underfunded root submission (should revert)
- ✅ Reentrancy attacks
- ✅ Access control violations

## Example Scenarios

### Scenario 1: Simple Direct Commission
```
Setup:
- Pool 0 configured with mlBps = [500, 300, 200] (5%, 3%, 2%)
- UserA creates referral voucher with directBps = 1000 (10%), transferOnUse = true
- Backend signs voucher with EIP-712

Flow:
- UserB stakes 1000 ECM using voucher
- PoolManager verifies voucher signature, extracts referrer = UserA, directBps = 1000
- PoolManager calls recordPurchaseAndPayDirect(hash, userB, userA, 0, 1000e18, ECM, 1000, true)
- ReferralModule:
  ✓ Links: referrerOf[userB] = userA
  ✓ Calculates: 1000 * 1000 / 10000 = 100 ECM
  ✓ Transfers 100 ECM to userA (transferOnUse = true)
  ✓ Emits DirectCommissionPaid

Result: UserA instantly receives 100 ECM
```

### Scenario 2: Multi-Level Reward Commission with Pool Configuration
```
Setup:
- Pool 0 configured with mlBps = [500, 300, 200] (5%, 3%, 2%)
- UserB referred by UserA (L1)
- UserA referred by UserX (L2)
- UserX referred by UserY (L3)
- Chain: UserB → UserA → UserX → UserY

Flow:
1. UserB claims 1000 ECM rewards from Pool 0
2. PoolManager emits RewardClaimRecorded(userB, 0, 1000e18, timestamp)
3. Off-chain engine:
   - Queries pool config: getPoolLevelConfig(0) = [500, 300, 200]
   - Queries chain: getReferralChain(userB, 10) = [userA, userX, userY]
   - Calculates:
     * userA: 1000 * 500 / 10000 = 50 ECM (L1)
     * userX: 1000 * 300 / 10000 = 30 ECM (L2)
     * userY: 1000 * 200 / 10000 = 20 ECM (L3)
   - Aggregates into Epoch 2025-W43
4. Admin funds 10,000 ECM (many claims aggregated)
5. Admin calls submitReferralPayoutRoot(202543, ECM, 10000e18, root, expiry)
6. UserA claims: claimReferral(202543, ECM, 50e18, proof)
7. UserX claims: claimReferral(202543, ECM, 30e18, proof)
8. UserY claims: claimReferral(202543, ECM, 20e18, proof)

Result: Each receives their multi-level commission from aggregated reward claims
```

### Scenario 3: Different Pools, Different Commission Structures
```
Setup:
- Pool 0: mlBps = [500, 300, 200] (5%, 3%, 2% - 3 levels)
- Pool 1: mlBps = [800, 400] (8%, 4% - 2 levels)
- Pool 2: mlBps = [300, 200, 100, 50] (3%, 2%, 1%, 0.5% - 4 levels)
- Same referral chain: UserB → UserA → UserX → UserY

Flow:
1. UserB claims 1000 ECM from Pool 0:
   - L1 (UserA): 1000 * 500 / 10000 = 50 ECM
   - L2 (UserX): 1000 * 300 / 10000 = 30 ECM
   - L3 (UserY): 1000 * 200 / 10000 = 20 ECM

2. UserB claims 1000 ECM from Pool 1:
   - L1 (UserA): 1000 * 800 / 10000 = 80 ECM
   - L2 (UserX): 1000 * 400 / 10000 = 40 ECM
   - L3 (UserY): 0 ECM (Pool 1 only has 2 levels)

3. UserB claims 1000 ECM from Pool 2:
   - L1 (UserA): 1000 * 300 / 10000 = 30 ECM
   - L2 (UserX): 1000 * 200 / 10000 = 20 ECM
   - L3 (UserY): 1000 * 100 / 10000 = 10 ECM
   - L4 (next referrer): 1000 * 50 / 10000 = 5 ECM

Result: Commission amounts vary by pool configuration
```

## Deployment Guide

### Step 1: Deploy ReferralModule
```javascript
const ReferralModule = await ethers.getContractFactory("ReferralModule");
const referralModule = await ReferralModule.deploy();
await referralModule.deployed();
console.log("ReferralModule deployed:", referralModule.address);
```

### Step 2: Configure ReferralModule
```javascript
// Set PoolManager as authorized caller
await referralModule.setPoolManager(poolManager.address);

// Configure pool-level multi-level commission rates
// Example: Pool 0 has 5%-3%-2% multi-level structure
await referralModule.setPoolLevelConfig(0, [500, 300, 200]); // [5%, 3%, 2%]

// Fund contract for direct commissions
await ecmToken.approve(referralModule.address, ethers.utils.parseEther("100000"));
await referralModule.fundContract(ecmToken.address, ethers.utils.parseEther("100000"));
```

### Step 3: Configure Pool-Specific Commission Rates
```javascript
// Different pools can have different commission structures
await referralModule.setPoolLevelConfig(1, [800, 400]); // Pool 1: 8%-4% (2 levels)
await referralModule.setPoolLevelConfig(2, [300, 200, 100, 50]); // Pool 2: 3%-2%-1%-0.5% (4 levels)

// Each pool's configuration is independent
const pool0Config = await referralModule.getPoolLevelConfig(0); // [500, 300, 200]
const pool1Config = await referralModule.getPoolLevelConfig(1); // [800, 400]
```

### Step 4: Update PoolManager
```javascript
// Set ReferralModule address in PoolManager
await poolManager.setReferralModule(referralModule.address);

// Set ReferralVoucher address in PoolManager (for EIP-712 verification)
await poolManager.setReferralVoucher(referralVoucher.address);
```

### Step 5: Deploy Off-Chain Engine
```bash
# Start event listener
npm run start:referral-engine

# Start API server for proof serving
npm run start:referral-api
```

## Monitoring & Analytics

### Key Metrics
- **Total Direct Commissions Paid**: `totalDirectPaid`
- **Total Multi-Level Commissions Paid**: `totalMultiLevelPaid`
- **Active Referral Codes**: Count of active codes
- **Total Referrer Links**: Count of `referrerOf` mappings
- **Pending Accruals**: Sum of `directAccrued` values
- **Epoch Claim Rate**: `claimed / totalAmount` per epoch

### Dashboard Queries
```javascript
// Total commissions paid
const totalDirect = await referralModule.totalDirectPaid();
const totalML = await referralModule.totalMultiLevelPaid();

// Referrer stats
const referrer = "0x...";
const accrued = await referralModule.getDirectAccrual(referrer);
const chain = await referralModule.getReferralChain(referrer, 10);

// Epoch stats
const epoch = 202543;
const [root, token, total, claimed, funded] = await referralModule.getPayoutRootInfo(epoch);
const claimRate = (claimed * 100) / total;
```

## Troubleshooting

### Common Issues

**Problem**: "InsufficientBalance" error on direct commission
**Solution**: Fund ReferralModule with ECM tokens via `fundContract()`

**Problem**: "InvalidConfig" error when setting pool config
**Solution**: Verify total mlBps ≤ 5000 (50%) and array length ≤ 10

**Problem**: "InvalidProof" error on claim
**Solution**: Ensure Merkle tree was built with sorted leaves, verify leaf format

**Problem**: Off-chain engine not processing claims
**Solution**: Check event listener connection, verify database has claim records, ensure pool config is tracked

**Problem**: "ReferrerAlreadySet" error
**Solution**: User can only be referred once; check existing referrer with `getReferrer()`

**Problem**: EIP-712 voucher verification fails
**Solution**: Ensure voucher signature is valid and backend uses correct domain separator

## Conclusion

The ReferralModule provides a robust, gas-efficient two-tier referral system:
- **Direct commissions** provide instant rewards for referrers
- **Multi-level reward commissions** enable network effects with off-chain calculation
- **Merkle proofs** allow cheap, auditable batch distributions
- **Security features** prevent gaming and fraud
- **Flexible configuration** supports various commission structures

Integration with PoolManager is minimal, maintaining separation of concerns while enabling powerful referral marketing capabilities.
