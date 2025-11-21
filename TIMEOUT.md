# Timeout Feature Documentation

## Overview

Added automatic timeout enforcement to prevent either party from indefinitely delaying transaction completion. If a party fails to confirm within 24 hours of their deadline, the other party can claim the defaulter's deposit.

## Timelock Rules

### Timeline

1. **Purchase Event** → Timer starts
2. **Seller has 24 hours** to confirm delivery
   - If seller fails: Buyer can claim timeout
3. **Seller Confirms** → New timer starts
4. **Buyer has 24 hours** to confirm receipt
   - If buyer fails: Seller can claim timeout

### Outcomes

#### Case 1: Seller Fails to Confirm (within 24 hours of purchase)

```
Buyer receives:
- Full ticket refund (ticketPrice × quantity)
- Buyer's deposit back ($50)
- Seller's deposit ($50)
Total: ticketCost + $100

Seller receives: Nothing (forfeits deposit)
Platform receives: Nothing
```

#### Case 2: Buyer Fails to Confirm (within 24 hours of seller confirmation)

```
Seller receives:
- Ticket payment (ticketPrice × quantity)
- Seller's deposit back ($50)
- Buyer's deposit ($50)
- Minus platform fees (3% + $1.25/ticket)

Platform receives:
- 3% platform fee
- $1.25 per ticket

Buyer receives: Nothing (forfeits deposit & payment)
```

## Smart Contract Changes

### Escrow.sol

**New State Variables:**

```solidity
uint256 public purchaseTimestamp;        // Set when escrow created
uint256 public sellerConfirmTimestamp;   // Set when seller confirms
uint256 private constant CONFIRMATION_DEADLINE = 24 hours;
```

**New Function:**

```solidity
function claimTimeout() external OnlyFactory
```

- Checks if 24 hours have passed since relevant deadline
- Transfers funds according to timeout rules
- Closes escrow

### Factory.sol

**New Function:**

```solidity
function claimTimeout(uint256 transactionId) external
```

- Only buyer or seller can call
- Cannot claim during dispute
- Cannot claim if already closed
- Delegates to escrow contract

## Usage Examples

### Seller Timeout Scenario

```solidity
// 1. Buyer purchases ticket
factory.purchaseTicket(transactionId);

// 2. Wait 24+ hours (seller never confirms)
vm.warp(block.timestamp + 24 hours + 1);

// 3. Buyer claims timeout
factory.claimTimeout(transactionId);

// Result: Buyer gets full refund + seller's deposit
```

### Buyer Timeout Scenario

```solidity
// 1. Buyer purchases ticket
factory.purchaseTicket(transactionId);

// 2. Seller confirms
factory.sellerConfirm(transactionId);

// 3. Wait 24+ hours (buyer never confirms)
vm.warp(block.timestamp + 24 hours + 1);

// 4. Seller claims timeout
factory.claimTimeout(transactionId);

// Result: Seller gets payment + buyer's deposit (minus fees)
```

## Test Coverage

**New Test File:** `test/Timeout.t.sol`

### Tests (6 total)

✅ **Positive Tests:**

1. `test_Timeout_SellerFailsToConfirm` - Buyer claims after seller timeout
2. `test_Timeout_BuyerFailsToConfirm` - Seller claims after buyer timeout
3. `test_Timeout_SellerClaimsAtExactDeadline` - Can claim exactly at 24-hour mark

✅ **Negative Tests:** 4. `test_RevertWhen_ClaimTimeoutTooEarly` - Cannot claim before 24 hours 5. `test_RevertWhen_ClaimTimeoutAfterBothConfirm` - Cannot claim if already complete 6. `test_RevertWhen_ClaimTimeoutDuringDispute` - Cannot claim during active dispute

### Test Results

```
Ran 6 tests for test/Timeout.t.sol:TimeoutTest
[PASS] test_RevertWhen_ClaimTimeoutAfterBothConfirm() (gas: 1492874)
[PASS] test_RevertWhen_ClaimTimeoutDuringDispute() (gas: 1433658)
[PASS] test_RevertWhen_ClaimTimeoutTooEarly() (gas: 1413127)
[PASS] test_Timeout_BuyerFailsToConfirm() (gas: 1500134)
[PASS] test_Timeout_SellerClaimsAtExactDeadline() (gas: 1490062)
[PASS] test_Timeout_SellerFailsToConfirm() (gas: 1424447)

All tests passed ✅
```

## Important Notes

1. **24-Hour Window:** Countdown starts from `block.timestamp`, using Ethereum block times
2. **No Grace Period:** Exactly 24 hours (86400 seconds) - can claim at exactly 24h00m00s
3. **Dispute Takes Priority:** Cannot claim timeout if a dispute is opened
4. **One-Time Claim:** Once claimed, escrow closes permanently
5. **Seller Must Confirm First:** Buyer's 24-hour timer only starts after seller confirms
6. **Platform Fees Apply:** When buyer times out, platform still receives fees from seller's payout

## Security Considerations

- ✅ Only buyer or seller can claim timeout
- ✅ Factory contract mediates all claims
- ✅ Escrow validates timing before releasing funds
- ✅ Cannot claim if escrow already closed
- ✅ Cannot claim if dispute is active
- ✅ Timestamps are immutable once set
- ✅ Uses `block.timestamp` which is resistant to minor manipulation

## Gas Costs

| Operation               | Gas Cost   |
| ----------------------- | ---------- |
| Claim Seller Timeout    | ~1,424,447 |
| Claim Buyer Timeout     | ~1,500,134 |
| Claim at Exact Deadline | ~1,490,062 |

## Integration

**Frontend should:**

1. Display countdown timer showing remaining time for confirmation
2. Show "Claim Timeout" button after 24 hours pass
3. Notify users via email/push when confirmation needed
4. Alert when timeout is approaching (e.g., 23 hours)
5. Auto-refresh to enable claim button once deadline passes

**Recommended User Notifications:**

- ⚠️ "15 minutes until confirmation deadline"
- ⚠️ "1 hour until confirmation deadline"
- 🔔 "You can now claim timeout compensation"

## Comparison with Disputes

| Feature         | Timeout                | Dispute                          |
| --------------- | ---------------------- | -------------------------------- |
| Who decides     | Automatic (time-based) | Resolver (human)                 |
| When available  | After 24h deadline     | Anytime before close             |
| Winner gets     | Forfeit deposit        | Forfeit + 30% of loser's deposit |
| Platform role   | Fee collection         | Fee + 70% of loser's deposit     |
| Who can trigger | Either party           | Either party                     |
| Reversible      | No                     | Yes (via resolver)               |

## Example Transaction Timeline

```
Day 0, 12:00 PM - Buyer purchases ticket
                  ↓ [Seller has 24 hours]
Day 1, 12:00 PM - Deadline for seller confirmation
                  ↓ [Buyer can claim timeout OR Seller confirms]
Day 1, 3:00 PM  - Seller confirms (3 hours late would be timeout)
                  ↓ [Buyer has 24 hours]
Day 2, 3:00 PM  - Deadline for buyer confirmation
                  ↓ [Seller can claim timeout OR Buyer confirms]
Day 2, 5:00 PM  - Buyer confirms
                  ✅ Transaction complete, funds released
```

## Total Test Suite Status

**37 Tests Total:**

- 6 E2E tests ✅
- 15 Factory unit tests ✅
- 10 Escrow unit tests ✅
- 6 Timeout tests ✅

All tests passing! 🎉
