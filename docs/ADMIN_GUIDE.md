# ECM Liquidity Mining Pool - Admin Guide

## 📋 Table of Contents

1. [System Architecture](#system-architecture)
2. [Deployment Guide](#deployment-guide)
3. [Pool Management](#pool-management)
4. [Reward Configuration](#reward-configuration)
5. [Liquidity Operations](#liquidity-operations)
6. [Referral System Management](#referral-system-management)
7. [Vesting Configuration](#vesting-configuration)
8. [Monitoring & Analytics](#monitoring--analytics)
9. [Security & Access Control](#security--access-control)
10. [Emergency Procedures](#emergency-procedures)
11. [Maintenance & Upgrades](#maintenance--upgrades)
12. [Troubleshooting](#troubleshooting)

---

## System Architecture

### Five-Contract Ecosystem

```
┌─────────────────────────────────────────────────────────┐
│                   POOLMANAGER                           │
│              (Core Sale, Stake, Rewards)                │
│  • USDT→ECM purchases at Uniswap spot price            │
│  • Auto-staking on purchase                             │
│  • 3 reward strategies (LINEAR/MONTHLY/WEEKLY)         │
│  • Early unstake penalties (configurable)              │
│  • Comprehensive analytics (15+ view functions)         │
└──────────┬──────────┬──────────┬──────────┬────────────┘
           │          │          │          │
     ┌─────▼────┐ ┌──▼───────┐ ┌▼────────┐ ┌▼────────────┐
     │REFERRAL  │ │REFERRAL  │ │VESTING  │ │LIQUIDITY    │
     │VOUCHER   │ │MODULE    │ │MANAGER  │ │MANAGER      │
     │          │ │          │ │         │ │             │
     │EIP-712   │ │2-Tier    │ │Linear   │ │Uniswap V2   │
     │Signature │ │Commission│ │Vesting  │ │Operations   │
     └──────────┘ └──────────┘ └─────────┘ └─────────────┘
```

### Contract Addresses (Example - Replace with Actual)

```
Network: Ethereum Mainnet (Chain ID: 1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PoolManager:         0x1234...abcd
ReferralVoucher:     0x2345...bcde
ReferralModule:      0x3456...cdef
VestingManager:      0x4567...def0
LiquidityManager:    0x5678...ef01

ECM Token:           0x6789...f012
USDT Token:          0xdAC17F958D2ee523a2206206994597C13D831ec7
Uniswap V2 Pair:     0x789a...0123
Uniswap V2 Router:   0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
```

### Key Design Patterns

**accRewardPerShare Pattern**: Canonical reward distribution (MasterChef-style)
```solidity
// Precision: 1e18 scaling
accRewardPerShare += (rewardAmount × 1e18) / totalStaked
userPending = (userStaked × accRewardPerShare / 1e18) - rewardDebt
```

**SafeERC20**: Handles non-standard tokens (USDT compatibility)

**ReentrancyGuard**: All state-changing functions protected

**Ownable + Pausable**: Emergency controls

---

## Deployment Guide

### Prerequisites Checklist

- [ ] Node.js 18+ installed
- [ ] Hardhat environment configured
- [ ] Private keys secured (use hardware wallet for mainnet)
- [ ] Sufficient ETH for gas (~0.3-0.5 ETH mainnet)
- [ ] ECM and USDT token addresses
- [ ] Uniswap V2 pair created (ECM/USDT)
- [ ] Treasury/multisig addresses prepared
- [ ] Etherscan API key for verification

### Deployment Order (CRITICAL)

**Phase 1: Independent Contracts**
```bash
1. ReferralVoucher (no dependencies)
2. ReferralModule (no dependencies)
```

**Phase 2: Core Contracts**
```bash
3. PoolManager (depends on Uniswap Router address)
4. VestingManager (depends on PoolManager address)
5. LiquidityManager (depends on Uniswap Router + Treasury)
```

### Step-by-Step Deployment

#### 1. Deploy ReferralVoucher

```javascript
// scripts/deploy-referral-voucher.js
const ReferralVoucher = await ethers.getContractFactory("ReferralVoucher");
const referralVoucher = await ReferralVoucher.deploy();
await referralVoucher.waitForDeployment();

console.log("ReferralVoucher deployed:", referralVoucher.target);

// Save address
fs.writeFileSync(
  'deployments.json',
  JSON.stringify({ referralVoucher: referralVoucher.target }, null, 2)
);
```

**Verify**:
```bash
npx hardhat verify --network mainnet 0xREFERRAL_VOUCHER_ADDRESS
```

---

#### 2. Deploy ReferralModule

```javascript
const ReferralModule = await ethers.getContractFactory("ReferralModule");
const referralModule = await ReferralModule.deploy();
await referralModule.waitForDeployment();

console.log("ReferralModule deployed:", referralModule.target);
```

**Verify**:
```bash
npx hardhat verify --network mainnet 0xREFERRAL_MODULE_ADDRESS
```

---

#### 3. Deploy PoolManager

```javascript
const UNISWAP_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

const PoolManager = await ethers.getContractFactory("PoolManager");
const poolManager = await PoolManager.deploy(UNISWAP_ROUTER);
await poolManager.waitForDeployment();

console.log("PoolManager deployed:", poolManager.target);
```

**Verify**:
```bash
npx hardhat verify --network mainnet 0xPOOL_MANAGER_ADDRESS "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
```

---

#### 4. Deploy VestingManager

```javascript
const VestingManager = await ethers.getContractFactory("VestingManager");
const vestingManager = await VestingManager.deploy(poolManager.target);
await vestingManager.waitForDeployment();

console.log("VestingManager deployed:", vestingManager.target);
```

**Verify**:
```bash
npx hardhat verify --network mainnet 0xVESTING_MANAGER_ADDRESS "0xPOOL_MANAGER_ADDRESS"
```

---

#### 5. Deploy LiquidityManager

```javascript
const TREASURY = "0xYOUR_TREASURY_OR_MULTISIG";

const LiquidityManager = await ethers.getContractFactory("LiquidityManager");
const liquidityManager = await LiquidityManager.deploy(
  UNISWAP_ROUTER,
  TREASURY
);
await liquidityManager.waitForDeployment();

console.log("LiquidityManager deployed:", liquidityManager.target);
```

**Verify**:
```bash
npx hardhat verify --network mainnet 0xLIQUIDITY_MANAGER_ADDRESS "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" "0xTREASURY_ADDRESS"
```

---

### Wire Contract Dependencies

**Critical Configuration Steps**:

```javascript
// 1. PoolManager → Set dependencies
await poolManager.setVestingManager(vestingManager.target);
await poolManager.setReferralVoucher(referralVoucher.target);
await poolManager.setReferralModule(referralModule.target);
await poolManager.addAuthorizedLiquidityManager(liquidityManager.target);

// 2. VestingManager → Authorize PoolManager
await vestingManager.addAuthorizedCreator(poolManager.target);

// 3. ReferralModule → Set PoolManager
await referralModule.setPoolManager(poolManager.target);
await referralModule.setReferralVoucher(referralVoucher.target);

// 4. ReferralVoucher → Authorize both PoolManager AND ReferralModule
await referralVoucher.setPoolManager(poolManager.target);
await referralVoucher.setReferralModule(referralModule.target); // CRITICAL: Dual authorization

// 5. ReferralVoucher → Add issuer (backend signing address)
const BACKEND_ISSUER = "0xYOUR_BACKEND_ADDRESS";
await referralVoucher.addIssuer(BACKEND_ISSUER);

// 6. LiquidityManager → Set PoolManager for callbacks
await liquidityManager.setPoolManager(poolManager.target);
```

---

### Post-Deployment Verification

```javascript
// Verify all connections
const checks = {
  poolManagerVesting: await poolManager.vestingManager(),
  poolManagerReferralVoucher: await poolManager.referralVoucher(),
  poolManagerReferralModule: await poolManager.referralModule(),
  vestingAuthorized: await vestingManager.authorizedCreators(poolManager.target),
  referralModulePoolManager: await referralModule.poolManager(),
  referralVoucherPoolManager: await referralVoucher.poolManager(),
  referralVoucherReferralModule: await referralVoucher.referralModule(), // Verify dual auth
  liquidityManagerPoolManager: await liquidityManager.poolManager()
};

console.log("Deployment Verification:", checks);

// All should return correct addresses
if (Object.values(checks).some(v => !v || v === ethers.ZeroAddress)) {
  throw new Error("❌ Deployment verification failed!");
}

console.log("✅ All contracts deployed and wired correctly!");
```

---

## Pool Management

### Create a New Pool

```javascript
const poolParams = {
  ecm: ECM_TOKEN_ADDRESS,
  usdt: USDT_TOKEN_ADDRESS,
  pair: UNISWAP_PAIR_ADDRESS,
  penaltyReceiver: TREASURY_ADDRESS,
  rewardStrategy: 0, // 0=LINEAR, 1=MONTHLY, 2=WEEKLY
  allowedStakeDurations: [
    30 * 24 * 3600,   // 30 days
    90 * 24 * 3600,   // 90 days
    180 * 24 * 3600   // 180 days - users select from these
  ],
  maxDuration: 180 * 24 * 3600, // 180 days (used for LINEAR rate calculation)
  vestingDuration: 180 * 24 * 3600, // 180 days vesting
  vestRewardsByDefault: false, // Don't force vesting
  penaltyBps: 2500 // 25% penalty (2500 basis points)
};

const tx = await poolManager.createPool(poolParams);
const receipt = await tx.wait();

// Get pool ID from event
const event = receipt.logs.find(log => log.fragment?.name === 'PoolCreated');
const poolId = event.args.poolId;

console.log(`✅ Pool ${poolId} created`);
```

### Pool Parameter Guide

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `ecm` | address | ECM token address | `0x1234...` |
| `usdt` | address | USDT token address | `0xdAC1...` |
| `pair` | address | Uniswap V2 ECM/USDT pair | `0x5678...` |
| `penaltyReceiver` | address | Where slashed tokens go | Treasury/Burn |
| `rewardStrategy` | uint8 | 0=LINEAR, 1=MONTHLY, 2=WEEKLY | `0` |
| `allowedStakeDurations` | uint256[] | User-selectable durations (seconds) | `[2592000, 7776000, 15552000]` (30, 90, 180 days) |
| `maxDuration` | uint256 | Maximum duration for rate calculations | `15552000` (180 days) |
| `vestingDuration` | uint256 | Reward vesting period | `15552000` |
| `vestRewardsByDefault` | bool | Force vesting on reward claims | `false` |
| `penaltyBps` | uint16 | Early unstake penalty (bps, max 10000) | `2500` (25%) |

---

### Allocate Tokens to Pool

```javascript
// Allocate ECM for sale (users can buy)
const SALE_ALLOCATION = ethers.parseEther("1000000"); // 1M ECM
await ecmToken.approve(poolManager.target, SALE_ALLOCATION);
await poolManager.allocateForSale(poolId, SALE_ALLOCATION);
console.log(`✅ Allocated ${ethers.formatEther(SALE_ALLOCATION)} ECM for sale`);

// Allocate ECM for rewards (staking rewards)
const REWARD_ALLOCATION = ethers.parseEther("500000"); // 500K ECM
await ecmToken.approve(poolManager.target, REWARD_ALLOCATION);
await poolManager.allocateForRewards(poolId, REWARD_ALLOCATION);
console.log(`✅ Allocated ${ethers.formatEther(REWARD_ALLOCATION)} ECM for rewards`);

// Check pool status
const pool = await poolManager.getPoolInfo(poolId);
console.log("Pool Status:", {
  allocatedForSale: ethers.formatEther(pool.allocatedForSale),
  allocatedForRewards: ethers.formatEther(pool.allocatedForRewards),
  sold: ethers.formatEther(pool.sold),
  totalStaked: ethers.formatEther(pool.totalStaked)
});
```

---

### Update Pool Configuration

```javascript
// Update allowed stake durations
await poolManager.setAllowedStakeDurations(poolId, [
  30 * 24 * 3600,   // 30 days
  60 * 24 * 3600,   // 60 days
  90 * 24 * 3600,   // 90 days
  180 * 24 * 3600   // 180 days
]);

// Update penalty configuration
await poolManager.setPenaltyConfig(
  poolId,
  2000, // 20% penalty (reduced from 25%)
  NEW_PENALTY_RECEIVER
);

// Update vesting configuration
await poolManager.setVestingConfig(
  poolId,
  365 * 24 * 3600, // 1 year vesting
  true // Force vesting by default
);

// Activate/Deactivate pool
await poolManager.setPoolActive(poolId, false); // Pause pool
await poolManager.setPoolActive(poolId, true);  // Resume pool
```

---

## Reward Configuration

### LINEAR Strategy Setup

**How It Works**: Constant reward rate per second, auto-calculated from remaining rewards and maxDuration.

```javascript
// After allocating rewards, set LINEAR rate
await poolManager.setLinearRewardRate(poolId);

// System auto-calculates:
// rewardRatePerSecond = remainingRewards / maxDuration

// Example: 500K ECM over 180 days
// Rate = 500,000 / (180 × 86400) = ~0.032 ECM/second
```

**Verify Rate**:
```javascript
const pool = await poolManager.getPoolInfo(poolId);
console.log("Reward Rate:", ethers.formatEther(pool.rewardRatePerSecond), "ECM/second");

// Calculate daily rewards
const dailyRewards = pool.rewardRatePerSecond * 86400n;
console.log("Daily Rewards:", ethers.formatEther(dailyRewards), "ECM/day");
```

**Update Rate** (after adding more rewards):
```javascript
// Allocate more rewards
await ecmToken.approve(poolManager.target, ethers.parseEther("100000"));
await poolManager.allocateForRewards(poolId, ethers.parseEther("100000"));

// Recalculate rate
await poolManager.setLinearRewardRate(poolId);
// New rate auto-calculated: (500K + 100K) / remaining_time
```

---

### MONTHLY Strategy Setup

**How It Works**: Different reward amounts per 30-day period.

```javascript
// Define monthly schedule (6 months)
const monthlyRewards = [
  ethers.parseEther("50000"),   // Month 1: 50K ECM
  ethers.parseEther("60000"),   // Month 2: 60K ECM
  ethers.parseEther("70000"),   // Month 3: 70K ECM
  ethers.parseEther("80000"),   // Month 4: 80K ECM
  ethers.parseEther("90000"),   // Month 5: 90K ECM
  ethers.parseEther("100000"),  // Month 6: 100K ECM
];

// Total: 450K ECM
const totalMonthly = monthlyRewards.reduce((sum, r) => sum + r, 0n);
console.log("Total Monthly Rewards:", ethers.formatEther(totalMonthly));

// Set schedule
await poolManager.setMonthlyRewards(poolId, monthlyRewards);
console.log("✅ Monthly schedule configured");
```

**Update Schedule** (extend or modify):
```javascript
// Add 3 more months
const extendedSchedule = [
  ...monthlyRewards,
  ethers.parseEther("110000"),  // Month 7
  ethers.parseEther("120000"),  // Month 8
  ethers.parseEther("130000")   // Month 9
];

await poolManager.setMonthlyRewards(poolId, extendedSchedule);
```

**Monitor Progress**:
```javascript
const pool = await poolManager.getPoolInfo(poolId);
console.log("Current Month Index:", pool.monthlyRewardIndex);
console.log("Completed Months:", pool.monthlyRewardIndex, "of", pool.monthlyRewards.length);
```

---

### WEEKLY Strategy Setup

**How It Works**: Different reward amounts per 7-day period.

```javascript
// Define weekly schedule (12 weeks = ~3 months)
const weeklyRewards = [
  ethers.parseEther("10000"),   // Week 1
  ethers.parseEther("12000"),   // Week 2
  ethers.parseEther("14000"),   // Week 3
  ethers.parseEther("16000"),   // Week 4
  ethers.parseEther("18000"),   // Week 5
  ethers.parseEther("20000"),   // Week 6
  ethers.parseEther("22000"),   // Week 7
  ethers.parseEther("24000"),   // Week 8
  ethers.parseEther("26000"),   // Week 9
  ethers.parseEther("28000"),   // Week 10
  ethers.parseEther("30000"),   // Week 11
  ethers.parseEther("32000")    // Week 12
];

// Set schedule
await poolManager.setWeeklyRewards(poolId, weeklyRewards);
console.log("✅ Weekly schedule configured for 12 weeks");
```

---

### Strategy Comparison Table

| Strategy | Best For | Pros | Cons |
|----------|----------|------|------|
| **LINEAR** | Long-term, stable projects | Predictable, simple | No flexibility |
| **MONTHLY** | Phased incentives | Can increase/decrease rewards | 30-day lock-in |
| **WEEKLY** | Short campaigns, testing | Fine-grained control | More management |

---

## Liquidity Operations

### Designate Liquidity Reserve

```javascript
// Mark portion of sold ECM for liquidity
const liquidityAmount = ethers.parseEther("100000"); // 100K ECM

await poolManager.setLiquidityReserve(poolId, liquidityAmount);
console.log(`✅ Set ${ethers.formatEther(liquidityAmount)} ECM as liquidity reserve`);
```

---

### Transfer to LiquidityManager

```javascript
// Transfer ECM and USDT to LiquidityManager
const ecmForLiquidity = ethers.parseEther("50000");  // 50K ECM
const usdtForLiquidity = ethers.parseUnits("25000", 6); // 25K USDT

await poolManager.transferToLiquidityManager(
  poolId,
  liquidityManager.target,
  ecmForLiquidity,
  usdtForLiquidity
);

console.log("✅ Transferred to LiquidityManager:");
console.log("  ECM:", ethers.formatEther(ecmForLiquidity));
console.log("  USDT:", ethers.formatUnits(usdtForLiquidity, 6));

// This updates pool.liquidityPoolOwedECM automatically
```

---

### Add Liquidity to Uniswap V2

```javascript
// LiquidityManager owner adds liquidity
const liquidityParams = {
  tokenA: ecmToken.target,
  tokenB: usdtToken.target,
  amountADesired: ecmForLiquidity,
  amountBDesired: usdtForLiquidity,
  amountAMin: ecmForLiquidity * 95n / 100n,    // 5% slippage
  amountBMin: usdtForLiquidity * 95n / 100n,   // 5% slippage
  to: TREASURY_ADDRESS, // LP tokens go here
  deadline: Math.floor(Date.now() / 1000) + 1800 // 30 minutes
};

const tx = await liquidityManager.addLiquidityWithTracking(
  liquidityParams,
  poolId,
  ecmToken.target
);
await tx.wait();

console.log("✅ Liquidity added to Uniswap V2");

// Check callback recorded
const pool = await poolManager.getPoolInfo(poolId);
console.log("Pool Liquidity Tracking:");
console.log("  ECM in Uniswap:", ethers.formatEther(pool.ecmAddedToUniswap));
console.log("  USDT in Uniswap:", ethers.formatUnits(pool.usdtAddedToUniswap, 6));
```

---

### Remove Liquidity (If Needed)

```javascript
// LiquidityManager owner removes liquidity
const lpTokenAmount = ethers.parseEther("100"); // LP tokens to burn

const removeParams = {
  tokenA: ecmToken.target,
  tokenB: usdtToken.target,
  liquidity: lpTokenAmount,
  amountAMin: 0, // Set actual minimums in production
  amountBMin: 0,
  to: owner.address,
  deadline: Math.floor(Date.now() / 1000) + 1800
};

await liquidityManager.removeLiquidity(removeParams);
console.log("✅ Liquidity removed from Uniswap");
```

---

### Refill PoolManager (Return Unused ECM)

```javascript
// If LiquidityManager has excess ECM, return to PoolManager
const refillAmount = ethers.parseEther("10000"); // 10K ECM

await ecmToken.connect(liquidityManagerOwner).approve(poolManager.target, refillAmount);
await liquidityManager.refillPoolManager(poolId, refillAmount);

console.log(`✅ Returned ${ethers.formatEther(refillAmount)} ECM to PoolManager`);

// This decreases pool.liquidityPoolOwedECM
```

---

## Referral System Management

### Configure Pool-Level Commission Rates

```javascript
// Set multi-level commission rates per pool
// [Level 1, Level 2, Level 3] in basis points (bps)
const levelConfig = [
  500,  // Level 1: 5%
  300,  // Level 2: 3%
  200   // Level 3: 2%
];

await referralModule.setPoolLevelConfig(poolId, levelConfig);
console.log("✅ Multi-level commission rates configured for pool", poolId);

// Constraints:
// - Max 10 levels
// - Total cannot exceed 5000 bps (50%)
```

**Example Configurations**:
```javascript
// Conservative (3 levels, 10% total)
const conservative = [500, 300, 200]; // 5%, 3%, 2%

// Aggressive (5 levels, 25% total)
const aggressive = [800, 600, 400, 300, 200]; // 8%, 6%, 4%, 3%, 2%

// Deep network (10 levels, 50% total)
const deep = [1000, 800, 600, 500, 400, 300, 200, 100, 50, 50];
```

---

### Add Voucher Issuer

```javascript
// Add backend signing address as authorized issuer
const BACKEND_ISSUER = "0xYOUR_BACKEND_SIGNER";
await referralVoucher.addIssuer(BACKEND_ISSUER);

console.log("✅ Added issuer:", BACKEND_ISSUER);

// Backend can now sign EIP-712 vouchers
```

---

### Generate Referral Vouchers (Backend)

```javascript
// Backend script to generate signed vouchers
const domain = {
  name: "ReferralVoucher",
  version: "1",
  chainId: 1, // Mainnet
  verifyingContract: referralVoucher.target
};

const types = {
  ReferralVoucher: [
    { name: "vid", type: "bytes32" },
    { name: "codeHash", type: "bytes32" },
    { name: "owner", type: "address" },
    { name: "directBps", type: "uint16" },
    { name: "transferOnUse", type: "bool" },
    { name: "expiry", type: "uint64" },
    { name: "maxUses", type: "uint32" },
    { name: "nonce", type: "uint256" }
  ]
};

// Create voucher
const code = "ALICE10";
const codeHash = ethers.keccak256(ethers.toUtf8Bytes(code));
const referrerAddress = "0xALICE...";
const nonce = Date.now(); // Unique per voucher

const vid = ethers.keccak256(
  ethers.solidityPacked(
    ["bytes32", "address", "uint256"],
    [codeHash, referrerAddress, nonce]
  )
);

const voucher = {
  vid,
  codeHash,
  owner: referrerAddress,
  directBps: 1000, // 10% direct commission
  transferOnUse: true, // Immediate transfer
  expiry: Math.floor(Date.now() / 1000) + (365 * 86400), // 1 year
  maxUses: 0, // Unlimited
  nonce
};

// Sign with backend issuer key
const signature = await backendSigner.signTypedData(domain, types, voucher);

// Store voucher + signature in database
// Serve to users via API endpoint: GET /api/vouchers/ALICE10
```

---

### Fund ReferralModule for Direct Commissions

```javascript
// Transfer ECM to ReferralModule for immediate commission payments
const commissionFund = ethers.parseEther("50000"); // 50K ECM

await ecmToken.approve(referralModule.target, commissionFund);
await referralModule.fundContract(ecmToken.target, commissionFund);

console.log(`✅ Funded ReferralModule with ${ethers.formatEther(commissionFund)} ECM`);

// Check balance
const balance = await ecmToken.balanceOf(referralModule.target);
console.log("ReferralModule ECM Balance:", ethers.formatEther(balance));
```

---

### Submit Multi-Level Commission Merkle Root

**Off-Chain Process** (runs on backend):

```javascript
// 1. Monitor RewardClaimRecorded events
const claimEvents = await referralModule.queryFilter(
  referralModule.filters.RewardClaimRecorded(),
  startBlock,
  endBlock
);

// 2. Calculate commissions for each claim
const commissions = new Map(); // beneficiary -> amount

for (const event of claimEvents) {
  const { claimant, poolId, rewardAmount } = event.args;
  
  // Get referral chain
  const chain = await referralModule.getReferralChain(claimant, 10);
  
  // Get pool config
  const levelConfig = await referralModule.getPoolLevelConfig(poolId);
  
  // Calculate per-level commissions
  for (let i = 0; i < levelConfig.length && i < chain.length; i++) {
    const referrer = chain[i];
    if (referrer === ethers.ZeroAddress) break;
    
    const commission = (rewardAmount * BigInt(levelConfig[i])) / 10000n;
    
    const key = `${referrer}-${ecmToken.target}`;
    commissions.set(key, (commissions.get(key) || 0n) + commission);
  }
}

// 3. Build Merkle tree
import { MerkleTree } from 'merkletreejs';

const leaves = Array.from(commissions.entries()).map(([key, amount]) => {
  const [beneficiary] = key.split('-');
  return ethers.solidityPackedKeccak256(
    ['address', 'address', 'uint256', 'uint256'],
    [beneficiary, ecmToken.target, amount, epochId]
  );
});

const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
const root = tree.getHexRoot();

// 4. Submit root on-chain
const totalAmount = Array.from(commissions.values()).reduce((sum, amt) => sum + amt, 0n);

await ecmToken.approve(referralModule.target, totalAmount);
await referralModule.submitReferralPayoutRoot(
  epochId,
  ecmToken.target,
  totalAmount,
  root,
  Math.floor(Date.now() / 1000) + (30 * 86400) // 30 days expiry
);

console.log(`✅ Submitted Merkle root for epoch ${epochId}`);
console.log(`   Total: ${ethers.formatEther(totalAmount)} ECM`);
console.log(`   Beneficiaries: ${commissions.size}`);

// 5. Store proofs in database for API serving
for (const [key, amount] of commissions) {
  const [beneficiary] = key.split('-');
  const leaf = ethers.solidityPackedKeccak256(
    ['address', 'address', 'uint256', 'uint256'],
    [beneficiary, ecmToken.target, amount, epochId]
  );
  const proof = tree.getHexProof(leaf);
  
  // Save to database: { epochId, beneficiary, amount, proof }
  await db.saveProof(epochId, beneficiary, amount, proof);
}
```

---

### Revoke Voucher (Emergency)

```javascript
// Revoke specific voucher by ID
const voucherId = "0x..."; // vid from voucher

await referralVoucher.revokeVoucher(voucherId);
console.log("✅ Voucher revoked:", voucherId);

// Voucher can no longer be used
```

---

## Vesting Configuration

### Update Vesting Duration

```javascript
// Change vesting period for a pool
await poolManager.setVestingConfig(
  poolId,
  365 * 24 * 3600, // 1 year vesting
  true // Force vesting by default
);

console.log("✅ Updated vesting config");
```

---

### Authorize Additional Vesting Creators

```javascript
// If you want another contract to create vestings
const ADDITIONAL_CREATOR = "0x...";
await vestingManager.addAuthorizedCreator(ADDITIONAL_CREATOR);

console.log("✅ Authorized creator:", ADDITIONAL_CREATOR);
```

---

### Revoke Vesting Schedule (Emergency)

```javascript
// Admin can revoke vesting if needed
const vestingId = 123;
await vestingManager.revokeVesting(vestingId);

console.log("✅ Vesting schedule revoked:", vestingId);

// User cannot claim unvested portions anymore
// Already vested amounts remain claimable
```

---

## Monitoring & Analytics

### Real-Time Pool Metrics

```javascript
// Get comprehensive pool status
const poolInfo = await poolManager.getPoolInfo(poolId);

console.log("Pool Metrics:");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Allocated for Sale:", ethers.formatEther(poolInfo.allocatedForSale));
console.log("Sold:", ethers.formatEther(poolInfo.sold));
console.log("Sale Progress:", (Number(poolInfo.sold) / Number(poolInfo.allocatedForSale) * 100).toFixed(2) + "%");
console.log("");
console.log("Allocated for Rewards:", ethers.formatEther(poolInfo.allocatedForRewards));
console.log("Rewards Paid:", ethers.formatEther(poolInfo.rewardsPaid));
console.log("Remaining Rewards:", ethers.formatEther(poolInfo.allocatedForRewards - poolInfo.rewardsPaid));
console.log("");
console.log("Total Staked:", ethers.formatEther(poolInfo.totalStaked));
console.log("Collected USDT:", ethers.formatUnits(poolInfo.collectedUSDT, 6));
console.log("Unique Stakers:", poolInfo.totalUniqueStakers);
```

---

### Calculate Pool APR

```javascript
// Get current APR for the pool
const periodsToProject = ethers.parseEther("1"); // 1 year for LINEAR
// For MONTHLY: 12 (months), for WEEKLY: 52 (weeks)

const apr = await poolManager.calculateAPR(poolId, periodsToProject);
console.log("Current APR:", ethers.formatUnits(apr, 16), "%"); // APR scaled by 1e18
```

---

### Pool Balance Status (Inventory Check)

```javascript
// Verify pool accounting integrity
const balanceStatus = await poolManager.getPoolBalanceStatus(poolId);

console.log("Pool Balance Status:");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Total Allocated:", ethers.formatEther(balanceStatus.totalAllocated));
console.log("Currently Staked:", ethers.formatEther(balanceStatus.currentlyStaked));
console.log("Rewards Paid:", ethers.formatEther(balanceStatus.rewardsPaid));
console.log("Liquidity Owed:", ethers.formatEther(balanceStatus.liquidityPoolOwedECM));
console.log("Available in Contract:", ethers.formatEther(balanceStatus.availableInContract));
console.log("Deficit:", ethers.formatEther(balanceStatus.deficit));

if (balanceStatus.deficit > 0n) {
  console.error("⚠️ WARNING: Accounting deficit detected!");
}
```

---

### Calculate Reward Depletion Time

```javascript
// Estimate when rewards will run out
const depletionInfo = await poolManager.calculateRewardDepletionTime(poolId);

console.log("Reward Depletion Forecast:");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Remaining Rewards:", ethers.formatEther(depletionInfo.remainingRewards));
console.log("Current Rate:", ethers.formatEther(depletionInfo.currentRewardRate), "ECM/second");
console.log("Estimated Depletion:", new Date(Number(depletionInfo.estimatedDepletionTime) * 1000).toLocaleString());
console.log("Days Remaining:", (Number(depletionInfo.estimatedDepletionTime - BigInt(Math.floor(Date.now() / 1000))) / 86400).toFixed(1));
```

---

### User Analytics

```javascript
// Get detailed user metrics
const userAddress = "0xUSER...";
const userAnalytics = await poolManager.getUserAnalytics(poolId, userAddress);

console.log("User Analytics for", userAddress);
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Has Staked:", userAnalytics.hasStaked);
console.log("First Stake:", new Date(Number(userAnalytics.firstStakeTimestamp) * 1000).toLocaleString());
console.log("Total Staked (Lifetime):", ethers.formatEther(userAnalytics.totalStaked));
console.log("Total Rewards Claimed:", ethers.formatEther(userAnalytics.totalRewardsClaimed));
console.log("Total Unstaked:", ethers.formatEther(userAnalytics.totalUnstaked));
```

---

### System-Wide Metrics

```javascript
// Platform health dashboard
const poolCount = await poolManager.poolCount();

let totalStaked = 0n;
let totalRewards = 0n;
let totalUSDT = 0n;
let totalUsers = 0;

for (let i = 0; i < poolCount; i++) {
  const pool = await poolManager.getPoolInfo(i);
  totalStaked += pool.totalStaked;
  totalRewards += pool.rewardsPaid;
  totalUSDT += pool.collectedUSDT;
  totalUsers += Number(pool.totalUniqueStakers);
}

const referralStats = {
  totalDirectPaid: await referralModule.totalDirectPaid(),
  totalMultiLevelPaid: await referralModule.totalMultiLevelPaid()
};

console.log("Platform Metrics:");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Active Pools:", poolCount);
console.log("Total Value Locked:", ethers.formatEther(totalStaked), "ECM");
console.log("Total Rewards Distributed:", ethers.formatEther(totalRewards), "ECM");
console.log("Total USDT Collected:", ethers.formatUnits(totalUSDT, 6), "USDT");
console.log("Total Unique Stakers:", totalUsers);
console.log("");
console.log("Referral System:");
console.log("  Direct Commissions:", ethers.formatEther(referralStats.totalDirectPaid), "ECM");
console.log("  Multi-Level Commissions:", ethers.formatEther(referralStats.totalMultiLevelPaid), "ECM");
```

---

## Security & Access Control

### Transfer Ownership to Multisig

```javascript
const MULTISIG_ADDRESS = "0xYOUR_GNOSIS_SAFE";

// Transfer all contracts to multisig
await poolManager.transferOwnership(MULTISIG_ADDRESS);
await referralModule.transferOwnership(MULTISIG_ADDRESS);
await referralVoucher.transferOwnership(MULTISIG_ADDRESS);
await vestingManager.transferOwnership(MULTISIG_ADDRESS);
await liquidityManager.transferOwnership(MULTISIG_ADDRESS);

console.log("✅ All contracts transferred to multisig:", MULTISIG_ADDRESS);
```

---

### Pause System (Emergency)

```javascript
// Pause PoolManager (stops all user operations)
await poolManager.pause();
console.log("⏸️ PoolManager paused");

// Resume when safe
await poolManager.unpause();
console.log("▶️ PoolManager resumed");
```

---

### Update Critical Addresses

```javascript
// Update VestingManager
await poolManager.setVestingManager(NEW_VESTING_MANAGER);

// Update ReferralVoucher
await poolManager.setReferralVoucher(NEW_REFERRAL_VOUCHER);

// Update ReferralModule
await poolManager.setReferralModule(NEW_REFERRAL_MODULE);

// Add new authorized LiquidityManager
await poolManager.addAuthorizedLiquidityManager(NEW_LIQUIDITY_MANAGER);

// Remove old LiquidityManager
await poolManager.removeAuthorizedLiquidityManager(OLD_LIQUIDITY_MANAGER);

console.log("✅ Critical addresses updated");
```

---

## Emergency Procedures

### Emergency Token Recovery

```javascript
// Recover mistakenly sent tokens (NOT user stakes!)
const mistakenlySentToken = "0xTOKEN...";
const amount = ethers.parseEther("1000");
const recipient = owner.address;

await poolManager.emergencyRecoverTokens(
  mistakenlySentToken,
  amount,
  recipient
);

console.log("✅ Recovered", ethers.formatEther(amount), "tokens");

// ⚠️ CRITICAL: This function has safeguards to prevent recovering user-staked ECM
```

---

### Withdraw Unclaimed Referral Commissions

```javascript
// After epoch expiry (30 days), recover unclaimed funds
const epochId = 202543;

const rootInfo = await referralModule.getPayoutRootInfo(epochId);
const unclaimed = rootInfo.totalAmount - rootInfo.claimed;

if (unclaimed > 0n && Date.now() / 1000 > rootInfo.expiry) {
  await referralModule.withdrawUnclaimed(epochId, TREASURY_ADDRESS);
  console.log(`✅ Withdrew ${ethers.formatEther(unclaimed)} unclaimed ECM from epoch ${epochId}`);
}
```

---

### Force Update Pool Rewards (If Stuck)

```javascript
// Manually trigger pool reward update
// Useful if reward strategy is stuck or needs synchronization
await poolManager.updatePoolRewards(poolId);
console.log("✅ Pool rewards updated");
```

---

### Revoke All Vesting for User (Extreme Emergency)

```javascript
// Get user's vesting schedules
const vestingIds = await vestingManager.getUserVestingIds(userAddress);

for (const vestingId of vestingIds) {
  await vestingManager.revokeVesting(vestingId);
  console.log(`✅ Revoked vesting ${vestingId}`);
}

console.log("⚠️ All vesting schedules revoked for", userAddress);
```

---

## Maintenance & Upgrades

### Adding More Sale Allocation

```javascript
// Pool running low on ECM for sale
const additionalSale = ethers.parseEther("500000"); // 500K more ECM

await ecmToken.approve(poolManager.target, additionalSale);
await poolManager.allocateForSale(poolId, additionalSale);

console.log(`✅ Added ${ethers.formatEther(additionalSale)} ECM for sale`);
```

---

### Extending Reward Duration

```javascript
// Add more rewards and update strategy

// For LINEAR: Just allocate more and call setLinearRewardRate()
await ecmToken.approve(poolManager.target, ethers.parseEther("200000"));
await poolManager.allocateForRewards(poolId, ethers.parseEther("200000"));
await poolManager.setLinearRewardRate(poolId); // Recalculates rate

// For MONTHLY: Extend schedule
const currentSchedule = await poolManager.getMonthlyRewards(poolId);
const extendedSchedule = [
  ...currentSchedule,
  ethers.parseEther("50000"), // Month N+1
  ethers.parseEther("50000")  // Month N+2
];
await poolManager.setMonthlyRewards(poolId, extendedSchedule);

console.log("✅ Reward duration extended");
```

---

### Update Uniswap Pair (If Migrated)

```javascript
// If ECM/USDT pair migrates to new address
const NEW_PAIR = "0xNEW_PAIR...";

// Create new pool with new pair
// Users must migrate stakes manually (cannot update existing pool pair)
```

---

## Troubleshooting

### Issue: Pool Balance Deficit

**Symptom**: `getPoolBalanceStatus()` shows non-zero deficit

**Causes**:
1. Accounting bug (unlikely - tested extensively)
2. Manual token transfers without proper tracking
3. Liquidity operations not recorded

**Solution**:
```javascript
// 1. Check actual ECM balance
const contractBalance = await ecmToken.balanceOf(poolManager.target);
console.log("Actual Balance:", ethers.formatEther(contractBalance));

// 2. Check expected balance
const balanceStatus = await poolManager.getPoolBalanceStatus(poolId);
console.log("Expected:", ethers.formatEther(balanceStatus.totalAllocated));

// 3. If deficit exists, allocate more to cover
const deficit = balanceStatus.deficit;
await ecmToken.transfer(poolManager.target, deficit);
await poolManager.allocateForSale(poolId, deficit); // or allocateForRewards

console.log("✅ Deficit covered");
```

---

### Issue: Reward Rate Zero

**Symptom**: `rewardRatePerSecond` is 0, no rewards accruing

**Causes**:
1. No rewards allocated
2. Reward strategy not configured
3. All rewards depleted

**Solution**:
```javascript
// Check reward allocation
const pool = await poolManager.getPoolInfo(poolId);
console.log("Allocated Rewards:", ethers.formatEther(pool.allocatedForRewards));
console.log("Paid Rewards:", ethers.formatEther(pool.rewardsPaid));

if (pool.allocatedForRewards === 0n) {
  // Allocate rewards
  await ecmToken.approve(poolManager.target, ethers.parseEther("100000"));
  await poolManager.allocateForRewards(poolId, ethers.parseEther("100000"));
  
  // Set strategy
  if (pool.rewardStrategy === 0) {
    await poolManager.setLinearRewardRate(poolId);
  }
  
  console.log("✅ Rewards configured");
}
```

---

### Issue: Merkle Proof Verification Failed

**Symptom**: Users can't claim multi-level commissions

**Causes**:
1. Leaf format mismatch
2. Tree not sorted
3. Wrong epoch ID

**Solution**:
```javascript
// Verify leaf calculation matches contract
const beneficiary = "0xUSER...";
const token = ecmToken.target;
const amount = ethers.parseEther("100");
const epochId = 202543;

// MUST match contract's keccak256(abi.encodePacked(...))
const leaf = ethers.solidityPackedKeccak256(
  ['address', 'address', 'uint256', 'uint256'],
  [beneficiary, token, amount, epochId]
);

console.log("Calculated Leaf:", leaf);

// Rebuild tree with sorted leaves
const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
const proof = tree.getHexProof(leaf);

console.log("Proof:", proof);

// Update database with correct proof
```

---

### Issue: Transaction Reverts with "SlippageExceeded"

**Symptom**: Users can't buy ECM

**Causes**:
1. Price volatility
2. Large order size
3. Low liquidity in Uniswap pair

**Solution**:
```javascript
// Check Uniswap pair liquidity
const pair = await ethers.getContractAt("IUniswapV2Pair", PAIR_ADDRESS);
const [reserve0, reserve1] = await pair.getReserves();

console.log("Uniswap Reserves:");
console.log("  Reserve0:", ethers.formatEther(reserve0));
console.log("  Reserve1:", ethers.formatUnits(reserve1, 6));

// If low liquidity, add more via LiquidityManager
// Instruct users to increase maxUsdtAmount tolerance
```

---

### Issue: Vesting Schedules Not Showing

**Symptom**: Users claim rewards but don't see vesting

**Causes**:
1. Vesting not enabled for pool
2. Frontend not querying VestingManager

**Solution**:
```javascript
// Check pool vesting config
const pool = await poolManager.getPoolInfo(poolId);
console.log("Vesting Enabled:", pool.vestRewardsByDefault);
console.log("Vesting Duration:", pool.vestingDuration / 86400, "days");

// Query user's vesting schedules
const vestingIds = await vestingManager.getUserVestingIds(userAddress);
console.log("User Vesting IDs:", vestingIds);

for (const vestingId of vestingIds) {
  const schedule = await vestingManager.getVestingInfo(vestingId);
  console.log(`  Vesting ${vestingId}:`, ethers.formatEther(schedule.amount), "ECM");
}
```

---

## Advanced Operations

### Batch Operations for Multiple Pools

```javascript
// Create multiple pools at once
const poolConfigs = [
  { /* Pool 1 config */ },
  { /* Pool 2 config */ },
  { /* Pool 3 config */ }
];

for (const config of poolConfigs) {
  const tx = await poolManager.createPool(config);
  await tx.wait();
  console.log(`✅ Created pool`);
}

// Allocate tokens to all pools
for (let i = 0; i < poolConfigs.length; i++) {
  await ecmToken.approve(poolManager.target, ALLOCATION_PER_POOL);
  await poolManager.allocateForSale(i, SALE_ALLOCATION);
  await poolManager.allocateForRewards(i, REWARD_ALLOCATION);
}
```

---

### Automated Reward Depletion Monitoring

```javascript
// Run this as a cron job
async function monitorRewardDepletion() {
  const poolCount = await poolManager.poolCount();
  
  for (let poolId = 0; poolId < poolCount; poolId++) {
    const depletionInfo = await poolManager.calculateRewardDepletionTime(poolId);
    const daysRemaining = (Number(depletionInfo.estimatedDepletionTime) - Date.now() / 1000) / 86400;
    
    if (daysRemaining < 7) {
      console.warn(`⚠️ Pool ${poolId} rewards depleting in ${daysRemaining.toFixed(1)} days`);
      // Send alert to admin
      sendAlert(`Pool ${poolId} rewards running low!`);
    }
  }
}

// Schedule every 6 hours
setInterval(monitorRewardDepletion, 6 * 3600 * 1000);
```

---


**Support Resources**:
- User Guide: [USER_GUIDE.md](./USER_GUIDE.md)
- Integration Guide: [integration-guide.md](../integration-guide.md)
- API Documentation: [API_UPDATE_GUIDE.md](./API_UPDATE_GUIDE.md)
- Architecture: [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md)


