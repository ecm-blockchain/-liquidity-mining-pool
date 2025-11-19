# Admin Interface Documentation - ECM Liquidity Mining Pool

**Version:** 1.0  
**Last Updated:** November 1, 2025  
**Audience:** Platform Administrators & Operators

---

## Table of Contents

1. [Admin Dashboard Overview](#1-admin-dashboard-overview)
2. [Pool Management](#2-pool-management)
3. [Token Allocation Management](#3-token-allocation-management)
4. [Reward Strategy Configuration](#4-reward-strategy-configuration)
5. [Liquidity Management](#5-liquidity-management)
6. [Referral System Administration](#6-referral-system-administration)
7. [Vesting Configuration](#7-vesting-configuration)
8. [Security Controls](#8-security-controls)
9. [Analytics & Reporting](#9-analytics--reporting)

---

## 1. Admin Dashboard Overview

### 1.1 Main Dashboard Screen

**Purpose:** High-level platform overview and quick actions

**Layout:**

#### Platform Statistics
```
┌───────────────────────────────────────────────────┐
│ Platform Overview                     [Last 24h]  │
├─────────────────┬─────────────────┬──────────────┤
│ Total TVL       │ Total Users     │ Total Volume │
│ $12.5M          │ 1,234           │ $850K        │
│ (+5.2%)         │ (+12)           │ (+$45K)      │
└─────────────────┴─────────────────┴──────────────┘

┌───────────────────────────────────────────────────┐
│ Token Metrics                         [Refresh]   │
├─────────────────┬─────────────────┬──────────────┤
│ ECM Price       │ ECM/USDT Depth  │ 24h Volume   │
│ $0.51           │ $2.5M           │ $350K        │
│ (+2.1%)         │ (+$100K)        │ (+15%)       │
└─────────────────┴─────────────────┴──────────────┘
```

#### Critical Alerts
```
┌────────────────────────────────────────────┐
│ ⚠️ Critical Alerts                         │
├────────────────────────────────────────────┤
│ HIGH: Pool #2 rewards depleting (2d left)  │
│ MED: Unusual unstake volume in Pool #1     │
│ LOW: Network gas prices elevated           │
└────────────────────────────────────────────┘
```

#### Quick Actions
```
┌────────────────────────────────────────────┐
│ Quick Actions                              │
├────────────────────────────────────────────┤
│ [Create Pool] [Allocate Tokens]            │
│ [Add Liquidity] [Emergency Pause]          │
└────────────────────────────────────────────┘
```

---

## 2. Pool Management

### 2.1 Pool Creation

**Purpose:** Create and configure new staking pools

```
┌────────────────────────────────────────────┐
│ Create New Pool                            │
├────────────────────────────────────────────┤
│ Basic Configuration                        │
├────────────────────────────────────────────┤
│ Pool Name:         [Standard Pool #1]      │
│ Description:       [First public pool...]  │
│                                            │
│ Token Configuration                        │
├────────────────────────────────────────────┤
│ ECM Address:       [0x1234...5678]         │
│ USDT Address:      [0xabcd...ef01]         │
│ Uniswap Pair:      [0x9876...5432]         │
│                                            │
│ Purchase Settings                          │
├────────────────────────────────────────────┤
│ Min Purchase:      [500] ECM               │
│ Purchase Multiple: [500] ECM               │
│                                            │
│ Staking Parameters                         │
├────────────────────────────────────────────┤
│ Lock Durations:                            │
│ ☑ 30 Days                                 │
│ ☑ 90 Days                                 │
│ ☑ 180 Days                                │
│                                            │
│ Early Unstake Penalty: [25] %              │
│ Penalty Receiver:   [Treasury Address]     │
│                                            │
│ [Cancel] [Create Pool]                    │
└────────────────────────────────────────────┘
```

### 2.2 Pool List & Management

**Purpose:** Overview and management of all pools

```
┌──────────────────────────────────────────────────────────────────┐
│ Active Pools (3)                              [+Create New Pool] │
├────────┬──────────┬────────────┬────────────┬──────────────────┤
│ ID     │ Status   │ TVL        │ Users      │ Actions          │
├────────┼──────────┼────────────┼────────────┼──────────────────┤
│ Pool#1 │ Active   │ $5.2M      │ 234        │ [Configure]      │
│        │ ●        │ (+2.1%)    │ (+5)       │ [Pause]         │
│        │          │            │            │                  │
│ Pool#2 │ Warning  │ $3.1M      │ 156        │ [Configure]      │
│        │ ●        │ (-0.5%)    │ (+2)       │ [Pause]         │
│        │          │            │            │                  │
│ Pool#3 │ Paused   │ $1.8M      │ 89         │ [Configure]      │
│        │ ●        │ (0%)       │ (0)        │ [Resume]        │
└────────┴──────────┴────────────┴────────────┴──────────────────┘
```

### 2.3 Individual Pool Management

**Purpose:** Detailed configuration and monitoring of a specific pool

```
┌────────────────────────────────────────────┐
│ Pool Balance Management                    │
├────────────────────────────────────────────┤
│ Token Accounting                           │
├────────────────────────────────────────────┤
│ User Stakes:        5.2M ECM              │
│ Liquidity Reserved: 1.5M ECM              │
│ Admin Allocated:    500K ECM              │
│ Contract Balance:   7.2M ECM              │
│                                            │
│ Balance Verification                       │
├────────────────────────────────────────────┤
│ Expected:           7.2M ECM              │
│ Actual:            7.2M ECM              │
│ Discrepancy:       0 ECM                  │
│                                            │
│ [Reconcile] [View Details]                │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Advanced Pool Settings                     │
├────────────────────────────────────────────┤
│ Penalty Configuration                      │
├────────────────────────────────────────────┤
│ Early Unstake:      [25] %                │
│ Grace Period:       [24] hours            │
│ Penalty Receiver:   [Treasury ▼]          │
│                                            │
│ ROI Simulation                             │
├────────────────────────────────────────────┤
│ Investment:        [10,000] USDT          │
│ Duration:          [180] days             │
│ Vesting:           [Yes ▼]                │
│                                            │
│ Projected Returns:                         │
│ ├─ Base:           45.2% APR              │
│ ├─ With Vesting:   48.5% APR              │
│ └─ Net USD:        $2,425                 │
│                                            │
│ [Run Simulation] [Update Settings]        │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Pool #1 Configuration                      │
├────────────────────────────────────────────┤
│ Pool Status: Active ●                      │
│                                            │
│ Pool Metrics                               │
├────────────────────────────────────────────┤
│ Total Staked:      5.2M ECM               │
│ Total Users:       234                     │
│ APR Range:         25% - 45%              │
│                                            │
│ Token Allocation                           │
├────────────────────────────────────────────┤
│ Sale Allocation:   10M ECM                 │
│ Sold:             6.2M ECM                 │
│ Rewards Reserved:  2M ECM                  │
│ Rewards Given:     450K ECM               │
│                                            │
│ Pool Parameters                            │
├────────────────────────────────────────────┤
│ Min Purchase:      [500] ECM              │
│ Purchase Multiple: [500] ECM              │
│ Penalty:          [25] %                  │
│ Treasury:         [0x1234...5678]         │
│                                            │
│ [Save Changes] [Emergency Pause]           │
└────────────────────────────────────────────┘
```

---

## 3. Token Allocation Management

### 3.1 Token Allocation Dashboard

**Purpose:** Manage ECM token allocations across pools

```
┌────────────────────────────────────────────┐
│ Token Allocation Overview                  │
├────────────────────────────────────────────┤
│ Total ECM Supply:     100,000,000         │
│                                            │
│ Allocated:            35,000,000 (35%)     │
│ ├─ Sale Pools:        20,000,000          │
│ ├─ Rewards:           10,000,000          │
│ └─ Liquidity:         5,000,000           │
│                                            │
│ Unallocated:         65,000,000 (65%)     │
│                                            │
│ [Allocate Tokens] [View Details]          │
└────────────────────────────────────────────┘
```

### 3.2 New Allocation Form

**Purpose:** Allocate tokens to pools for sale or rewards

```
┌────────────────────────────────────────────┐
│ Allocate Tokens                            │
├────────────────────────────────────────────┤
│ Select Pool:        [Pool #1 ▼]           │
│                                            │
│ Allocation Type:                           │
│ ○ For Sale                                │
│ ● For Rewards                             │
│                                            │
│ Amount:            [1,000,000] ECM        │
│                                            │
│ Current Pool Allocation:                   │
│ Sale:              5,000,000 ECM          │
│ Rewards:           2,000,000 ECM          │
│                                            │
│ [Calculate Impact] [Allocate]             │
└────────────────────────────────────────────┘
```

### 3.3 Liquidity Reserve Management

**Purpose:** Manage tokens reserved for liquidity

```
┌────────────────────────────────────────────┐
│ Liquidity Reserve Management               │
├────────────────────────────────────────────┤
│ Total Reserved:     5,000,000 ECM         │
│                                            │
│ Current Liquidity                          │
├────────────────────────────────────────────┤
│ Uniswap V2 Pairs:                         │
│ ECM/USDT:          2,500,000 ECM          │
│ Value:             $1,275,000             │
│                                            │
│ Available:         2,500,000 ECM          │
│                                            │
│ [Add Liquidity] [Remove Liquidity]        │
└────────────────────────────────────────────┘
```

---

## 4. Reward Strategy Configuration

### 4.1 Reward Strategy Management

**Purpose:** Configure and monitor reward distribution strategies

```
┌────────────────────────────────────────────┐
│ Advanced Reward Configuration              │
├────────────────────────────────────────────┤
│ Select Strategy Type                       │
├────────────────────────────────────────────┤
│ ○ LINEAR    - Fixed rate per second       │
│ ○ MONTHLY   - Monthly distribution        │
│ ● WEEKLY    - Weekly distribution         │
│                                            │
│ Weekly Strategy Settings                   │
├────────────────────────────────────────────┤
│ Base Weekly Rate:   [5000] ECM            │
│ Duration:           [52] weeks            │
│ Distribution Day:   [Monday ▼]            │
│ Time:              [00:00 UTC]            │
│                                            │
│ Week-by-Week Adjustment                    │
├────────────────────────────────────────────┤
│ Week 1-4:          100% of base           │
│ Week 5-12:         90% of base            │
│ Week 13-24:        80% of base            │
│ Week 25-52:        70% of base            │
│                                            │
│ [Preview Schedule] [Save Strategy]        │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Price Oracle Configuration                 │
├────────────────────────────────────────────┤
│ Current Settings                           │
├────────────────────────────────────────────┤
│ Price Source:      Uniswap V2 TWAP        │
│ Update Interval:   [5] minutes            │
│ TWAP Period:       [30] minutes           │
│                                            │
│ Price Bounds                               │
├────────────────────────────────────────────┤
│ Min Price:         [$0.45]                │
│ Max Price:         [$0.55]                │
│ Deviation Alert:   [5] %                  │
│                                            │
│ [Update Settings] [View Price History]    │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Pool #1 Reward Strategy                    │
├────────────────────────────────────────────┤
│ Current Strategy: LINEAR                   │
│                                            │
│ Strategy Configuration                     │
├────────────────────────────────────────────┤
│ Type:              [LINEAR ▼]             │
│                                            │
│ LINEAR Settings                            │
├────────────────────────────────────────────┤
│ Rate:              [100] ECM per day       │
│ Duration:          [365] days             │
│ Total:             36,500 ECM             │
│                                            │
│ - OR -                                     │
│                                            │
│ MONTHLY Settings                           │
├────────────────────────────────────────────┤
│ Month 1:           [5,000] ECM            │
│ Month 2:           [4,500] ECM            │
│ Month 3:           [4,000] ECM            │
│ [+ Add Month]                             │
│                                            │
│ [Preview Distribution] [Save Strategy]     │
└────────────────────────────────────────────┘
```

### 4.2 APR Configuration

**Purpose:** Set and monitor APR levels for different lock periods

```
┌────────────────────────────────────────────┐
│ Pool #1 APR Configuration                  │
├────────────────────────────────────────────┤
│ Duration APRs                              │
├────────────────────────────────────────────┤
│ 30 Days:           [25] %                 │
│ Base APR + Duration Bonus                  │
│                                            │
│ 90 Days:           [35] %                 │
│ Base APR + Duration Bonus                  │
│                                            │
│ 180 Days:          [45] %                 │
│ Base APR + Duration Bonus                  │
│                                            │
│ [Calculate Rewards] [Update APRs]          │
└────────────────────────────────────────────┘
```

### 4.3 Reward Monitoring

**Purpose:** Track reward distribution and projections

```
┌────────────────────────────────────────────┐
│ Pool #1 Reward Monitoring                  │
├────────────────────────────────────────────┤
│ Reward Status                              │
├────────────────────────────────────────────┤
│ Allocated:         2,000,000 ECM          │
│ Distributed:       450,000 ECM            │
│ Reserved:          550,000 ECM            │
│ Available:         1,000,000 ECM          │
│                                            │
│ Distribution Rate                          │
├────────────────────────────────────────────┤
│ Current Rate:      5,000 ECM/day          │
│ Projected Empty:   200 days               │
│ Recommend Action:  Allocate more          │
│                                            │
│ [View Details] [Allocate More]            │
└────────────────────────────────────────────┘
```

---

## 5. Liquidity Management

### 5.1 Liquidity Overview

**Purpose:** Monitor and manage Uniswap V2 liquidity

```
┌────────────────────────────────────────────┐
│ Liquidity Position Management              │
├────────────────────────────────────────────┤
│ LP Token Details                           │
├────────────────────────────────────────────┤
│ Total LP Balance:   75,000 LP              │
│ ├─ In Treasury:     60,000 LP              │
│ ├─ In Staking:      10,000 LP              │
│ └─ Unallocated:     5,000 LP               │
│                                            │
│ Position Value                             │
├────────────────────────────────────────────┤
│ ECM Value:          $2.55M                 │
│ USDT Value:         $2.55M                 │
│ Total Value:        $5.1M                  │
│                                            │
│ [Manage LP Tokens] [View Analytics]        │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Advanced Liquidity Controls                │
├────────────────────────────────────────────┤
│ Slippage Protection                        │
├────────────────────────────────────────────┤
│ Max Slippage:      [1.0] %                │
│ Price Impact:      [2.0] %                │
│ Min Tx Delay:      [3] blocks             │
│                                            │
│ Treasury Management                        │
├────────────────────────────────────────────┤
│ Treasury Address:   [0x9876...5432]       │
│ Auto-compound:     [✓] Enabled            │
│ Compound Interval: [24] hours             │
│                                            │
│ [Update Settings] [View History]          │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Liquidity Migration Tools                  │
├────────────────────────────────────────────┤
│ Migration Status: No active migration      │
│                                            │
│ Quick Actions                              │
├────────────────────────────────────────────┤
│ [Start Migration]                         │
│ [Pause Migration]                         │
│ [Complete Migration]                      │
│                                            │
│ Current Migration                          │
├────────────────────────────────────────────┤
│ From: V2 Pool                              │
│ To: New V2 Pool                           │
│ Progress: 0/100%                          │
│                                            │
│ [View Details] [Cancel Migration]         │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Liquidity Management                       │
├────────────────────────────────────────────┤
│ ECM/USDT Pool                              │
├────────────────────────────────────────────┤
│ Total Liquidity:   $5.2M                  │
│ ECM Reserved:      5.1M ECM               │
│ USDT Reserved:     2.6M USDT              │
│ Current Price:     $0.51/ECM              │
│                                            │
│ 24h Stats                                  │
├────────────────────────────────────────────┤
│ Volume:            $850K                   │
│ Fees Earned:       $2,550                  │
│ Price Change:      +2.1%                   │
│                                            │
│ [Manage Liquidity] [View Analytics]        │
└────────────────────────────────────────────┘
```

### 5.2 Add Liquidity Form

**Purpose:** Add liquidity to Uniswap V2 pairs

```
┌────────────────────────────────────────────┐
│ Add Liquidity                              │
├────────────────────────────────────────────┤
│ Select Pair:       [ECM/USDT ▼]           │
│                                            │
│ Amount ECM:        [100,000]              │
│ Value:             $51,000                 │
│                                            │
│ Amount USDT:       [51,000]               │
│                                            │
│ Price Impact:      0.15%                   │
│ New Pool Share:    2.5%                    │
│                                            │
│ Slippage Tolerance:[0.5] %                │
│                                            │
│ [Preview] [Add Liquidity]                 │
└────────────────────────────────────────────┘
```

### 5.3 Liquidity Removal Form

**Purpose:** Remove liquidity from Uniswap V2 pairs

```
┌────────────────────────────────────────────┐
│ Remove Liquidity                           │
├────────────────────────────────────────────┤
│ Select Pair:       [ECM/USDT ▼]           │
│                                            │
│ Amount to Remove:  [25] %                 │
│                                            │
│ You Will Receive:                          │
│ ECM:              25,000                   │
│ USDT:             12,750                   │
│                                            │
│ Price Impact:      0.08%                   │
│ New Pool Share:    1.875%                  │
│                                            │
│ [Preview] [Remove Liquidity]              │
└────────────────────────────────────────────┘
```

---

## 6. Referral System Administration

### 6.1 Referral System Overview

**Purpose:** Manage referral program configuration

```
┌────────────────────────────────────────────┐
│ Referral System                            │
├────────────────────────────────────────────┤
│ System Statistics                          │
├────────────────────────────────────────────┤
│ Total Referrers:   234                     │
│ Total Referred:    1,890                   │
│ Total Commission:   45,000 ECM             │
│                                            │
│ Commission Structure                       │
├────────────────────────────────────────────┤
│ Level 1:           [5] %                  │
│ Level 2:           [2] %                  │
│ Level 3:           [1] %                  │
│                                            │
│ [Update Rates] [View Analytics]            │
└────────────────────────────────────────────┘
```

### 6.2 Voucher Management

**Purpose:** Create and manage referral vouchers

```
┌────────────────────────────────────────────┐
│ Referral Vouchers                          │
├────────────────────────────────────────────┤
│ Create Vouchers                            │
├────────────────────────────────────────────┤
│ Quantity:          [100]                   │
│ Commission Rate:   [7.5] %                 │
│ Valid Until:       [Dec 31, 2025]         │
│ Max Uses:          [1] per voucher        │
│                                            │
│ [Generate Vouchers]                        │
│                                            │
│ Active Vouchers                            │
├────────────────────────────────────────────┤
│ Total:             500                     │
│ Used:              234                     │
│ Available:         266                     │
│                                            │
│ [Export List] [Revoke Selected]           │
└────────────────────────────────────────────┘
```

### 6.3 Commission Management

**Purpose:** Monitor and manage referral commissions

```
┌────────────────────────────────────────────┐
│ Commission Management                      │
├────────────────────────────────────────────┤
│ Commission Overview                        │
├────────────────────────────────────────────┤
│ Pending:           12,500 ECM             │
│ Paid Today:        2,500 ECM              │
│ Total Paid:        45,000 ECM             │
│                                            │
│ Top Referrers                             │
├────────────────────────────────────────────┤
│ 1. 0x1234: 5,000 ECM (100 refs)          │
│ 2. 0xabcd: 3,500 ECM (75 refs)           │
│ 3. 0x9876: 2,800 ECM (60 refs)           │
│                                            │
│ [View All] [Export Report]                │
└────────────────────────────────────────────┘
```

---

## 7. Vesting Configuration

### 7.1 Vesting Setup

**Purpose:** Configure vesting schedules and parameters

```
┌────────────────────────────────────────────┐
│ Multi-Token Vesting Control                │
├────────────────────────────────────────────┤
│ Supported Tokens                           │
├────────────────────────────────────────────┤
│ ● ECM Token         [✓] Enabled           │
│   [0x1234...5678]   [Configure]          │
│                                            │
│ ● LP Tokens         [✓] Enabled           │
│   [0xabcd...ef01]   [Configure]          │
│                                            │
│ ● Other Token       [ ] Disabled          │
│   [Add New Token]                         │
│                                            │
│ Batch Operations                           │
├────────────────────────────────────────────┤
│ [Create Multiple] [Revoke Selected]       │
│ [Modify Batch] [Export Schedules]         │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Emergency Controls                         │
├────────────────────────────────────────────┤
│ Vesting Emergency Actions                  │
├────────────────────────────────────────────┤
│ ⚠️ Requires multisig approval             │
│                                            │
│ [Pause All Vesting]                       │
│ [Force Revoke All]                        │
│ [Emergency Withdraw]                       │
│                                            │
│ Token Allowance Management                │
├────────────────────────────────────────────┤
│ ECM Allowance:     1,000,000              │
│ LP Allowance:      50,000                 │
│                                            │
│ [Update Allowances] [View History]        │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Vesting Configuration                      │
├────────────────────────────────────────────┤
│ Default Settings                           │
├────────────────────────────────────────────┤
│ Duration:          [180] days             │
│ Cliff Period:      [0] days               │
│ Release Frequency: [Daily ▼]              │
│                                            │
│ Pool Settings                              │
├────────────────────────────────────────────┤
│ Auto-Vest Rewards:                         │
│ Pool #1:           [✓]                    │
│ Pool #2:           [✓]                    │
│ Pool #3:           [ ]                    │
│                                            │
│ [Update Settings]                         │
└────────────────────────────────────────────┘
```

### 7.2 Vesting Schedule Management

**Purpose:** Monitor and manage vesting schedules

```
┌────────────────────────────────────────────┐
│ Active Vesting Schedules                   │
├────────────────────────────────────────────┤
│ Total Vesting:     1,234,567 ECM          │
│ Total Released:    456,789 ECM            │
│ Total Pending:     777,778 ECM            │
│                                            │
│ Schedule List                              │
├────────────────────────────────────────────┤
│ 1. Pool #1 Rewards                         │
│    Total: 500K ECM                        │
│    Released: 250K ECM (50%)               │
│    [View Details] [Modify]                │
│                                            │
│ 2. Pool #2 Rewards                         │
│    Total: 734K ECM                        │
│    Released: 206K ECM (28%)               │
│    [View Details] [Modify]                │
│                                            │
│ [Create New] [Export Data]                │
└────────────────────────────────────────────┘
```

---

## 8. Security Controls

### 8.1 Access Control

**Purpose:** Manage admin roles and permissions

```
┌────────────────────────────────────────────┐
│ Admin Access Control                       │
├────────────────────────────────────────────┤
│ Role Management                            │
├────────────────────────────────────────────┤
│ Super Admin                                │
│ ├─ 0x1234...5678 (Owner)                  │
│ └─ 0xabcd...ef01                          │
│                                            │
│ Pool Manager                               │
│ ├─ 0x2345...6789                          │
│ └─ 0xbcde...f012                          │
│                                            │
│ Reward Manager                             │
│ └─ 0x3456...7890                          │
│                                            │
│ [Add Admin] [Modify Roles]                │
└────────────────────────────────────────────┘
```

### 8.2 Emergency Controls

**Purpose:** Emergency functions and system pause

```
┌────────────────────────────────────────────┐
│ ⚠️ Emergency Controls                      │
├────────────────────────────────────────────┤
│ System Status: ACTIVE                      │
│                                            │
│ Quick Actions                              │
├────────────────────────────────────────────┤
│ [Pause All Pools]                         │
│ [Pause New Stakes]                        │
│ [Pause Unstaking]                         │
│ [Pause Rewards]                           │
│                                            │
│ Emergency Recovery                         │
├────────────────────────────────────────────┤
│ [Recover Stuck Tokens]                    │
│ [Force Unstake All]                       │
│                                            │
│ ⚠️ Requires owner multisig (3/5)          │
└────────────────────────────────────────────┘
```

### 8.3 Transaction Monitoring

**Purpose:** Monitor high-risk transactions

```
┌────────────────────────────────────────────┐
│ Transaction Monitoring                     │
├────────────────────────────────────────────┤
│ High-Risk Transactions                     │
├────────────────────────────────────────────┤
│ Large Stakes (>$50K):      5              │
│ Large Unstakes (>$50K):    3              │
│ Failed Transactions:        12             │
│ Unusual Patterns:          2              │
│                                            │
│ [View Details] [Export Report]            │
└────────────────────────────────────────────┘
```

---

## 9. Analytics & Reporting

### 9.1 Platform Analytics

**Purpose:** Comprehensive platform metrics and analysis

```
┌────────────────────────────────────────────┐
│ Platform Analytics                         │
├────────────────────────────────────────────┤
│ Time Period: [Last 30 Days ▼]             │
│                                            │
│ Key Metrics                                │
├────────────────────────────────────────────┤
│ New Users:          +234                   │
│ Total Volume:       $12.5M                 │
│ Avg Stake Size:     $5,340                 │
│ Retention Rate:     85%                    │
│                                            │
│ Pool Performance                           │
├────────────────────────────────────────────┤
│ Most Active:        Pool #1                │
│ Highest APR:        Pool #2                │
│ Best Retention:     Pool #3                │
│                                            │
│ [Generate Report] [Export Data]           │
└────────────────────────────────────────────┘
```

### 9.2 Financial Reports

**Purpose:** Generate financial and operational reports

```
┌────────────────────────────────────────────┐
│ Financial Reporting                        │
├────────────────────────────────────────────┤
│ Report Type:        [Daily Summary ▼]      │
│                                            │
│ Include Metrics                            │
├────────────────────────────────────────────┤
│ ☑ Token Sales                             │
│ ☑ Reward Distribution                     │
│ ☑ Liquidity Changes                       │
│ ☑ Fee Collection                          │
│ ☑ Referral Payments                       │
│                                            │
│ Format: [PDF ▼]                           │
│                                            │
│ [Generate Report] [Schedule Reports]       │
└────────────────────────────────────────────┘
```

### 9.3 User Analytics

**Purpose:** User behavior and engagement metrics

```
┌────────────────────────────────────────────┐
│ User Analytics                             │
├────────────────────────────────────────────┤
│ User Segments                              │
├────────────────────────────────────────────┤
│ By Stake Size:                            │
│ ├─ Whale (>$100K):     45                 │
│ ├─ Large ($10K-100K):  234                │
│ ├─ Medium ($1K-10K):   567                │
│ └─ Small (<$1K):       890                │
│                                            │
│ By Duration:                              │
│ ├─ 180 Days:           456                │
│ ├─ 90 Days:            567                │
│ └─ 30 Days:            234                │
│                                            │
│ [View Details] [Export Data]              │
└────────────────────────────────────────────┘
```

---

