# ECM Liquidity Mining Pool - User Guide

## 📖 Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [How to Buy & Stake ECM](#how-to-buy--stake-ecm)
4. [Understanding Your Rewards](#understanding-your-rewards)
5. [How to Claim Rewards](#how-to-claim-rewards)
6. [How to Unstake](#how-to-unstake)
7. [Using Referral Codes](#using-referral-codes)
8. [Adding Referral Code Later](#adding-referral-code-later)
9. [Understanding Vesting](#understanding-vesting)
10. [Dashboard & Portfolio](#dashboard--portfolio)
11. [FAQ](#faq)
12. [Troubleshooting](#troubleshooting)

---

## Introduction

Welcome to the **ECM Liquidity Mining Pool**! This platform allows you to:

✅ **Buy ECM tokens** with USDT at market price  
✅ **Automatically stake** your ECM to earn rewards  
✅ **Earn referral commissions** by sharing your codes  
✅ **Claim rewards** instantly or with vesting  
✅ **Unstake anytime** with clear penalty rules  

### Key Benefits

- 🎯 **No Lock Period**: Unstake anytime (penalty applies if early)
- 💰 **Multiple Reward Strategies**: LINEAR, MONTHLY, or WEEKLY distribution
- 🔗 **Referral System**: Earn commissions on purchases and rewards
- 🎁 **Vesting Options**: Spread rewards over time for better planning
- 📊 **Real-Time Analytics**: Track your earnings and projections

---

## Getting Started

### What You Need

1. **Crypto Wallet** (e.g., MetaMask)
2. **USDT tokens** (for purchasing ECM)
3. **ECM** (for gas fees)
4. **(Optional) Referral code** from a friend

### Minimum Requirements

- **Minimum Purchase**: 500 ECM

### Supported Networks

- ECM Mainnet

---

## How to Buy & Stake ECM

### Step 1: Connect Your Wallet

1. Visit the platform website
2. Click "Connect Wallet"
3. Approve the connection in your wallet

### Step 2: Approve USDT

Before your first purchase, you need to approve USDT spending:

1. Navigate to the "Buy & Stake" section
2. Click "Approve USDT"
3. Confirm the transaction in your wallet

⚠️ **Note**: This is a one-time step. Gas fee applies.

### Step 3: Buy and Stake ECM

#### Option A: Specify Maximum USDT Amount (Recommended)

```
Example:
- You want to spend: Up to 1,000 USDT
- Current ECM price: 0.1 USDT per ECM
- System will calculate: ~10,000 ECM (floored to 10,000)
- You'll actually spend: ~1,000 USDT (exact amount)
```

**Steps**:
1. Enter maximum USDT amount you're willing to spend
2. Select stake duration (choose from available options, e.g., 30/90/180 days)
3. *(Optional)* Enter referral code if you have one
4. Click "Buy & Stake"
5. Review transaction details
6. Confirm in your wallet

#### Option B: Specify Exact ECM Amount

```
Example:
- You want: Exactly 5,000 ECM
- Current price: 0.1 USDT per ECM
- Required USDT: ~500 USDT
- You must have: At least 500 USDT + slippage tolerance
```

**Steps**:
1. Enter exact ECM amount (must be multiple of 500)
2. System shows required USDT amount
3. Select stake duration
4. *(Optional)* Enter referral code
5. Click "Buy Exact ECM & Stake"
6. Confirm transaction

### Step 4: Transaction Confirmation

After confirmation, you'll see:
- ✅ ECM purchased and staked
- ✅ Stake duration started
- ✅ Referral recorded (if used)
- 📊 Your position displayed on dashboard

### Understanding Slippage

**Slippage** is the difference between expected and actual price due to market movement.

- **Low Slippage**: Small purchases, stable prices
- **High Slippage**: Large purchases, volatile prices

💡 **Tip**: The system automatically protects you with `maxUsdtAmount`. If price moves too much, transaction reverts (you don't lose funds).

---

## Understanding Your Rewards

### Reward Strategies

The pool admin configures one of three reward distribution strategies:

#### 1. LINEAR Strategy

**How it works**: Constant reward rate per second over the entire pool duration.

```
Example:
- Pool has 100,000 ECM rewards
- Duration: 180 days
- Your stake: 10,000 ECM
- Total staked: 100,000 ECM

Your daily rewards: (100,000 / 180) × (10,000 / 100,000) = ~55.5 ECM/day
```

**Pros**: 
- Predictable daily rewards
- Simple to calculate

**Cons**:
- Rewards don't change over time

---

#### 2. MONTHLY Strategy

**How it works**: Different reward amounts released each month (30-day periods).

```
Example:
- Month 1: 5,000 ECM
- Month 2: 10,000 ECM
- Month 3: 15,000 ECM
Your stake: 10,000 ECM
Total staked: 100,000 ECM (10% share)

Your rewards:
- Month 1: 500 ECM
- Month 2: 1,000 ECM
- Month 3: 1,500 ECM
```

**Pros**:
- Can have increasing/decreasing incentives
- Aligns with business goals

**Cons**:
- Rewards vary by month

---

#### 3. WEEKLY Strategy

**How it works**: Different reward amounts released each week (7-day periods).

```
Example:
- Week 1-4: 1,000 ECM/week
- Week 5-8: 2,000 ECM/week
Your stake: 5,000 ECM
Total staked: 50,000 ECM (10% share)

Your rewards:
- Weeks 1-4: 100 ECM/week
- Weeks 5-8: 200 ECM/week
```

**Pros**:
- Shorter distribution cycles
- More granular control

**Cons**:
- More complex tracking

---

### How Rewards Accumulate

Rewards accrue **every second** you're staked using the `accRewardPerShare` pattern:

```
Your Pending Rewards = (Your Stake × accRewardPerShare / 1e18) - Your Reward Debt
```

**Real-Time Calculation**:
- Dashboard updates every 10 seconds
- Rewards never stop accumulating (24/7)
- No manual action needed

---

## How to Claim Rewards

You have two options for claiming rewards:

### Option 1: Claim Without Unstaking

**Use Case**: You want to keep earning while taking some profit.

**Steps**:
1. Go to your dashboard
2. See "Pending Rewards" amount
3. Click "Claim Rewards"
4. Choose instant claim or vesting (if enabled)
5. Confirm transaction

**Result**:
- ✅ Rewards sent to your wallet (or vesting schedule created)
- ✅ Your stake remains active
- ✅ Continue earning rewards

---

### Option 2: Claim When Unstaking

**Use Case**: You want to exit your position completely.

**Steps**:
1. Click "Unstake"
2. Review:
   - Principal amount
   - Pending rewards
   - Penalty (if early)
3. Confirm transaction

**Result**:
- ✅ Principal returned (minus penalty if early)
- ✅ Rewards sent (or vested)
- ✅ Position closed

---

### Vesting (If Enabled by Pool)

Some pools vest rewards to reduce sell pressure. If vesting is enabled:

**Instant Claim (Vesting Disabled)**:
- Rewards sent directly to your wallet
- Available immediately

**Vested Claim (Vesting Enabled)**:
- Rewards locked in VestingManager contract
- Release linearly over vesting period (e.g., 180 days)
- You can claim vested portions anytime

**Example**:
```
Reward Claimed: 1,000 ECM
Vesting Duration: 180 days

Day 0: 0 ECM claimable
Day 45: 250 ECM claimable (25%)
Day 90: 500 ECM claimable (50%)
Day 180: 1,000 ECM claimable (100%)
```

**To Claim Vested Tokens**:
1. Go to "Vesting" section
2. See vested schedules
3. Click "Claim Vested" for each schedule
4. Receive unlocked tokens

---

## How to Unstake

### Understanding Early Unstaking

**Business Requirement**: The system allows unstaking anytime BUT applies an economic penalty if you unstake before your selected duration ends.

#### Key Points:

✅ **No Minimum Lock**: You can always unstake  
⚠️ **25% Penalty**: Default penalty on principal if early (configurable by pool admin)  
✅ **Rewards Protected**: Rewards are NEVER penalized  
⏰ **Maturity**: No penalty after your selected duration passes  

---

### Early Unstake Example

```
Your Position:
- Staked: 10,000 ECM
- Duration: 90 days
- Time passed: 30 days
- Pending rewards: 500 ECM

You decide to unstake early:

Principal:
  Original: 10,000 ECM
  Penalty (25%): 2,500 ECM (goes to treasury)
  You receive: 7,500 ECM

Rewards:
  Pending: 500 ECM
  Penalty: 0 ECM (NEVER penalized)
  You receive: 500 ECM

Total received: 8,000 ECM
```

---

### Mature Unstake Example

```
Your Position:
- Staked: 10,000 ECM
- Duration: 90 days
- Time passed: 90+ days
- Pending rewards: 1,500 ECM

You unstake after maturity:

Principal:
  Original: 10,000 ECM
  Penalty: 0 ECM (matured!)
  You receive: 10,000 ECM

Rewards:
  Pending: 1,500 ECM
  Penalty: 0 ECM
  You receive: 1,500 ECM

Total received: 11,500 ECM
```

---

### Unstaking Steps

1. Go to your dashboard
2. Click "Unstake"
3. See penalty preview:
   - ⚠️ "Early Unstake: 2,500 ECM penalty"
   - ✅ "Mature: No penalty"
4. Review breakdown:
   - Principal returned: X ECM
   - Rewards claimed: Y ECM
   - Total: X + Y ECM
5. Confirm transaction

---

### Penalty Calculator (Before Unstaking)

Use the built-in calculator to see exact amounts:

```
📊 Penalty Calculator

Current Status: EARLY (45 days remaining)
Penalty Rate: 25%

If you unstake now:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Principal:        10,000 ECM
Penalty:          -2,500 ECM
Principal Return:  7,500 ECM

Rewards:           1,000 ECM (no penalty)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Received:    8,500 ECM

If you wait 45 days:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Principal:        10,000 ECM (no penalty)
Projected Rewards: 1,500 ECM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Received:   11,500 ECM
```

💡 **Tip**: The calculator helps you decide if waiting is worth it!

---

## Using Referral Codes

### How Referral Codes Work

The platform uses a **two-tier referral system**:

1. **Direct Commission** (Tier 1): When someone uses your code to buy ECM
2. **Multi-Level Commission** (Tier 2): When they claim rewards later

---

### Using Someone's Referral Code

#### When Buying ECM

**Benefits**:
- Support your referrer
- Build referral chain for future multi-level rewards
- One-time relationship (permanent)

**Steps**:
1. During purchase, see "Referral Code (Optional)" field
2. Enter code (e.g., "ALICE10")
3. System validates code
4. Complete purchase
5. ✅ You're now linked to that referrer forever

**What Happens**:
- Referrer earns instant commission (e.g., 5-10% of your staked amount)
- You become part of their referral network
- Your future reward claims generate multi-level commissions

---

### Getting Your Own Referral Code

**To become a referrer**:
1. Contact platform admin or create voucher via backend
2. Receive unique voucher signature
3. Share code with friends

**Your Earnings**:

**Tier 1: Direct Commission**
```
Friend stakes: 10,000 ECM
Your commission rate: 5% (500 bps)
You earn instantly: 500 ECM
```

**Tier 2: Multi-Level Commission**
```
Friend claims rewards: 1,000 ECM
Pool config: [5%, 3%, 2%] (you're Level 1)
You earn: 50 ECM (5% of reward)
```

---

### Referral Network Example

```
Level 1 (You): Alice
  └─ Refers Bob → Alice earns 5% of Bob's purchases/rewards
     └─ Bob refers Carol → Alice earns 3% of Carol's rewards
        └─ Carol refers Dave → Alice earns 2% of Dave's rewards

Multi-Level Commission Distribution:
- Bob claims 1,000 ECM rewards
  → Alice gets 50 ECM (Level 1)
  
- Carol claims 1,000 ECM rewards
  → Bob gets 50 ECM (Level 1)
  → Alice gets 30 ECM (Level 2)
  
- Dave claims 1,000 ECM rewards
  → Carol gets 50 ECM (Level 1)
  → Bob gets 30 ECM (Level 2)
  → Alice gets 20 ECM (Level 3)
```

---

### Claiming Referral Commissions

#### Direct Commissions

**If Immediate Transfer**:
- Commissions sent to your wallet instantly when someone stakes using your code
- No action needed

**If Accrued**:
1. Go to "Referrals" section
2. See "Accrued Balance"
3. Click "Withdraw Accrued"
4. Confirm transaction

---

#### Multi-Level Commissions (Merkle-Based)

Multi-level commissions are batched and distributed via Merkle proofs:

**Steps**:
1. Backend monitors reward claims
2. Calculates your multi-level commissions
3. Batches into epochs (e.g., weekly)
4. Publishes Merkle root on-chain
5. You claim with proof

**How to Claim**:
1. Check "Claimable Epochs" on dashboard
2. See available amounts per epoch
3. Click "Claim Epoch X"
4. System fetches your Merkle proof
5. Confirm transaction
6. Receive your ECM

**Example**:
```
📊 Claimable Commissions

Epoch 202543 (Nov 1-7, 2024)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Level 1: 45.5 ECM
Level 2: 23.2 ECM
Level 3: 12.8 ECM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total: 81.5 ECM
[Claim Now]

Epoch 202544 (Nov 8-14, 2024)
Available in: 3 days
```

---

## Adding Referral Code Later

### New Feature: Post-Purchase Referrer Setting

**What if you forgot to use a referral code during purchase?**

✅ **Good News**: You can add it later! (One time only)

---

### How It Works

1. You initially buy/stake ECM **without** a referral code
2. Friend shares their code with you later
3. You can add the code **once** to build referral relationship
4. Future reward claims generate multi-level commissions

⚠️ **Important Limitations**:
- **One-time only**: Once set, cannot change referrer
- **No retroactive**: Doesn't affect past staking/rewards
- **Future only**: Only affects future reward claim commissions
- **No direct commission**: No immediate payment (since no new purchase)

---

### Steps to Add Referrer Later

#### Option A: Direct Call to ReferralModule (Advanced)

```
1. Get valid referral voucher from friend
2. Go to ReferralModule contract
3. Call setMyReferrer(voucherInput, signature)
4. Confirm transaction
```

#### Option B: Via PoolManager Interface (Recommended)

```
1. Go to platform dashboard
2. Click "Add Referral Code"
3. Enter voucher information
4. Click "Link Referrer"
5. Confirm transaction
```

---

### Example Scenario

```
Timeline:

Day 1: You buy 10,000 ECM (no referral code)
  - Staked: 10,000 ECM
  - Referrer: None

Day 30: Friend shares code "ALICE10"
  - You call setMyReferrer(ALICE10)
  - ✅ Now: referrerOf[you] = Alice

Day 60: You claim 500 ECM rewards
  - Alice earns 5% × 500 = 25 ECM (Level 1)
  - Alice's referrer earns 3% × 500 = 15 ECM (Level 2)

Day 90: You claim 500 ECM more rewards
  - Same multi-level distribution applies
```

**What Alice DOESN'T Get**:
- ❌ No direct commission from your original 10,000 ECM stake
- ❌ No commissions from rewards claimed before Day 30

**What Alice DOES Get**:
- ✅ Multi-level commissions from all future reward claims
- ✅ Permanent referral relationship

---

### Verification

After setting referrer, verify on dashboard:

```
📊 Referral Status

Your Referrer: 0xAlice... (ALICE10)
Linked On: Nov 15, 2024
Status: ✅ Active

Future reward claims will generate:
- Level 1 commission for Alice: 5%
- Level 2+ commissions for Alice's upline
```

---

## Dashboard & Portfolio

### Main Dashboard Sections

#### 1. Staking Overview

```
📊 Your Staking Position

Pool: ECM/USDT Pool #1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Staked:           10,000 ECM
Stake Duration:   90 days
Time Remaining:   45 days
Status:           🟡 Active (Early)

Rewards:
Pending:          1,234.56 ECM
Claimed:          567.89 ECM
Total Earned:     1,802.45 ECM

Value:
Staked:           $1,000 (@ $0.10/ECM)
Rewards:          $123.45
Total Value:      $1,123.45
ROI:              12.3%

[Claim Rewards]  [Unstake]
```

---

#### 2. Referral Earnings

```
💰 Referral Dashboard

Direct Commissions (Tier 1):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Paid Out:         2,500 ECM
Accrued:          150 ECM
[Withdraw Accrued]

Multi-Level Commissions (Tier 2):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Earned:     3,450 ECM
Claimable Now:    250 ECM (Epoch 202543)
[Claim Commissions]

Your Network:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Direct Referrals:     12 users
Total Network:        48 users (3 levels deep)
Network Volume:       125,000 ECM staked
```

---

#### 3. Vesting Schedule

```
🔒 Vesting Schedules

Schedule #1 (from Reward Claim on Oct 15)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Amount:     1,000 ECM
Vested So Far:    250 ECM (25%)
Claimable Now:    150 ECM
Already Claimed:  100 ECM

Progress: ▓▓▓▓▓▓▓░░░░░░░░░░░░░░░ 25%

[Claim Vested] (150 ECM)

Schedule #2 (from Reward Claim on Nov 1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Amount:     500 ECM
Vested So Far:    50 ECM (10%)
Claimable Now:    50 ECM
Already Claimed:  0 ECM

Progress: ▓▓░░░░░░░░░░░░░░░░░░░░ 10%

[Claim Vested] (50 ECM)
```

---

#### 4. Analytics & Charts

**APR Chart**:
```
📈 Annual Percentage Rate (APR)

Current APR: 45.2%

    60% │
        │              ╭─────────────
    50% │         ╭────╯
        │    ╭────╯
    40% │────╯
        │
    30% │
        └─────────────────────────────
       Oct    Nov    Dec    Jan    Feb
```

**Rewards Accumulation**:
```
📊 Rewards Earned Over Time

Total: 1,802 ECM

2000│
    │                        ╱
1500│                   ╱
    │              ╱
1000│         ╱
    │    ╱
 500│╱
    └─────────────────────────────
   Day 1  30    60    90   120  150
```

---

### Portfolio Summary

```
💼 Complete Financial View

Total Assets:       15,234 ECM ($1,523.40)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Breakdown:
  Staked Principal:   10,000 ECM (65.6%)
  Pending Rewards:     1,234 ECM (8.1%)
  Vested (locked):     1,500 ECM (9.8%)
  Referral Accrued:      150 ECM (1.0%)
  Claimable Now:       2,350 ECM (15.4%)

Actions:
[Claim All Rewards]  [View Details]
```

---

## FAQ

### General Questions

**Q: What is the minimum purchase?**  
A: 500 ECM, and purchases must be in multiples of 500 ECM.

**Q: Can I buy with ETH or other tokens?**  
A: No, currently only USDT is accepted. You can swap other tokens for USDT on DEXes.

**Q: Where does the ECM come from?**  
A: From the pool's allocated tokens. Admin pre-funds pools with ECM for sale and rewards.

**Q: Is my stake locked?**  
A: No hard lock. You can unstake anytime, but early unstaking incurs a 25% penalty on principal (default).

---

### Staking Questions

**Q: What happens to my ECM after purchase?**  
A: It's automatically staked in the same transaction. You cannot hold idle ECM in the contract.

**Q: Can I add more to my stake?**  
A: Yes! Just make another purchase. Each purchase creates a separate stake position with its own duration.

**Q: What's the best stake duration?**  
A: Longer durations avoid early penalties. Choose based on your liquidity needs. 90-180 days is common.

**Q: How often can I claim rewards?**  
A: Anytime! Rewards accrue continuously and can be claimed as often as you like.

---

### Reward Questions

**Q: How are rewards calculated?**  
A: Using the `accRewardPerShare` pattern. Your share of rewards is proportional to your stake relative to total pool stake.

**Q: What's the difference between LINEAR, MONTHLY, and WEEKLY strategies?**  
A: 
- **LINEAR**: Constant daily rate
- **MONTHLY**: Different amounts per month
- **WEEKLY**: Different amounts per week

**Q: When do rewards stop?**  
A: When pool rewards are fully distributed or pool duration ends.

**Q: Can rewards run out?**  
A: Yes, if pool is heavily utilized. Check pool analytics for "reward runway" days remaining.

---

### Penalty Questions

**Q: Why is there a penalty?**  
A: Economic design to discourage early exits and stabilize the pool. You have full freedom to exit, but at a cost.

**Q: Is the penalty always 25%?**  
A: No, it's configurable per pool. Check your pool's `penaltyBps` (2500 = 25%).

**Q: Are my rewards also penalized?**  
A: **No!** Rewards are NEVER penalized. Only principal is subject to early unstake penalty.

**Q: What happens to penalty tokens?**  
A: Sent to `penaltyReceiver` address (usually treasury or burn address).

**Q: Can I avoid the penalty?**  
A: Yes, wait until your stake duration passes. After maturity, no penalty applies.

---

### Referral Questions

**Q: How do I get a referral code?**  
A: Contact platform admin or register via the platform (if self-service is enabled).

**Q: Can I use multiple codes?**  
A: No, only one referrer per account. Once set, it's permanent.

**Q: Do I earn less if I use someone's code?**  
A: No! Commissions come from the pool's allocation, not from your stake or rewards.

**Q: When do I receive referral commissions?**  
A: 
- **Direct**: Instantly (or accrued for later withdrawal)
- **Multi-level**: Batched into epochs, claim with Merkle proof

**Q: Can I change my referrer?**  
A: No, referrer relationships are immutable once set.

**Q: What if I forgot to use a referral code?**  
A: You can add it later using `setMyReferrer()`, but it only affects future rewards, not past staking.

---

### Vesting Questions

**Q: Why are my rewards vested?**  
A: Pool admin may enable vesting to reduce sell pressure and align long-term incentives.

**Q: How do I know if vesting is enabled?**  
A: Check pool info: `vestRewardsByDefault` field. Also shown during claim.

**Q: Can I choose to vest or not?**  
A: Depends on pool configuration. Some pools force vesting, others let you choose.

**Q: When can I claim vested tokens?**  
A: Anytime! Vesting is linear, so you can claim unlocked portions as they vest.

**Q: What happens if I don't claim vested tokens?**  
A: They keep accumulating. No expiry. Claim whenever convenient.

---

### Technical Questions

**Q: What is accRewardPerShare?**  
A: A mathematical pattern for fair reward distribution. Ensures each staker gets their proportional share regardless of when they join/leave.

**Q: Why do I need to approve USDT?**  
A: ERC-20 tokens require approval before contracts can spend them. Standard DeFi practice.

**Q: What's the contract address?**  
A: Check platform footer or documentation. Always verify on Etherscan before interacting.

**Q: Is the contract audited?**  
A: [Check documentation for audit reports]

**Q: What if I send tokens directly to contract?**  
A: Use `emergencyRecoverTokens()` (if mistakenly sent). Contact admin for assistance.

---

## Troubleshooting

### Common Issues

#### Transaction Failed: "InsufficientAllowance"

**Problem**: USDT not approved or approval too low.

**Solution**:
1. Go to USDT token contract
2. Call `approve(PoolManager, amount)`
3. Retry purchase

---

#### Transaction Failed: "SlippageExceeded"

**Problem**: Price moved too much between quote and execution.

**Solution**:
1. Increase `maxUsdtAmount` tolerance
2. Split large orders into smaller ones
3. Try during lower volatility periods

---

#### Transaction Failed: "BelowMinimum"

**Problem**: ECM amount < 500 or not a multiple of 500.

**Solution**:
1. Use calculator to find valid amount
2. Ensure exactly 500, 1000, 1500, etc.

---

#### Transaction Failed: "InsufficientLiquidity"

**Problem**: Uniswap pair doesn't have enough liquidity for your purchase size.

**Solution**:
1. Reduce purchase amount
2. Wait for liquidity additions
3. Check pool status

---

#### Can't See Pending Rewards

**Problem**: Dashboard shows 0 rewards despite being staked.

**Solution**:
1. Check pool status: Is it active?
2. Verify reward allocation: Are rewards available?
3. Check pool strategy: Is current month/week funded?
4. Refresh browser cache

---

#### Claim Transaction Reverts

**Problem**: "NothingToClaim" error.

**Solution**:
1. Wait a bit longer (rewards accrue over time)
2. Check `pendingRewards()` view function
3. Ensure pool has reward balance

---

#### Referral Code Not Working

**Problem**: "InvalidVoucher" or "VoucherExpired" error.

**Solution**:
1. Verify code hasn't expired
2. Check code hasn't been revoked
3. Ensure code hasn't hit usage limit
4. Contact code issuer

---

#### Can't Find Vesting Schedule

**Problem**: Claimed rewards but don't see vesting.

**Solution**:
1. Check if vesting was enabled for that pool
2. Go to VestingManager contract directly
3. Call `getUserVestingIds(yourAddress)`
4. Check each vesting ID

---


### Strategy Tips

💡 **Maximize Earnings**:
1. **Stake Early**: Earlier stakers get more rewards before pool dilutes
2. **Compound**: Claim and restake rewards periodically
3. **Referrals**: Share codes to earn passive income
4. **Duration**: Match stake duration to your liquidity needs
5. **Monitor APR**: Track changes and adjust strategy

💡 **Risk Management**:
1. **Diversify**: Don't put all funds in one pool
2. **Start Small**: Test with small amounts first
3. **Understand Penalties**: Know early unstake costs
4. **Track Maturity**: Set calendar reminders
5. **Monitor Pool Health**: Check reward runway

---

**Remember**:
- ✅ Always buy in 500 ECM increments
- ✅ Choose stake duration wisely (no hard lock, but penalties apply)
- ✅ Rewards accrue continuously and are never penalized
- ✅ Use referral codes to build passive income
- ✅ Monitor your dashboard for opportunities

**Need Help?**
- Read the [Admin Guide](./ADMIN_GUIDE.md) for technical details
- Check [Integration Guide](../integration-guide.md) for developers
