# Test Suite Documentation

## Overview

Comprehensive test suite for the SeatSwap ticket marketplace contracts using Foundry.

## Test Statistics

- **Total Tests:** 31
- **Unit Tests:** 25 (FactoryUnit: 15, EscrowUnit: 10)
- **E2E Tests:** 6
- **Status:** ✅ All tests passing

## Running Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run specific test file
forge test --match-contract E2ETest
forge test --match-contract FactoryUnitTest
forge test --match-contract EscrowUnitTest

# Run specific test
forge test --match-test test_E2E_SuccessfulTransaction

# Run with very verbose output (shows traces)
forge test -vvv
```

## Test Coverage

### FactoryUnit.t.sol (15 tests)

**Positive Tests:**

- ✅ `test_Constructor` - Verifies initial contract state
- ✅ `test_ListTicket` - Tests successful ticket listing
- ✅ `test_PurchaseTicket` - Tests buyer purchasing a ticket
- ✅ `test_CloseListing` - Tests seller canceling listing before sale
- ✅ `test_AddResolver` - Tests owner adding a dispute resolver
- ✅ `test_RemoveResolver` - Tests owner removing a resolver
- ✅ `test_CloseFactory` - Tests owner closing the factory

**Negative Tests (vm.expectRevert):**

- ✅ `test_RevertWhen_ListTicketWithoutDeposit` - Fails without approval
- ✅ `test_RevertWhen_ListTicketZeroPrice` - Fails with 0 price
- ✅ `test_RevertWhen_ListTicketZeroQuantity` - Fails with 0 quantity
- ✅ `test_RevertWhen_PurchaseOwnTicket` - Seller can't buy own ticket
- ✅ `test_RevertWhen_CloseListingWithBuyer` - Can't cancel after purchase
- ✅ `test_RevertWhen_AddResolverNotOwner` - Only owner can add resolvers
- ✅ `test_RevertWhen_RemoveOwnerAsResolver` - Owner can't be removed
- ✅ `test_RevertWhen_ListTicketWhenClosed` - Can't list when factory closed

### EscrowUnit.t.sol (10 tests)

**Positive Tests:**

- ✅ `test_Constructor` - Verifies escrow initialization
- ✅ `test_PartyConfirmation` - Tests dual confirmation and payment release
- ✅ `test_OpenDispute` - Tests dispute opening
- ✅ `test_ResolveDisputeBuyerWins` - Tests buyer winning dispute
- ✅ `test_ResolveDisputeSellerWins` - Tests seller winning dispute

**Negative Tests (vm.expectRevert):**

- ✅ `test_RevertWhen_PartyConfirmationNotFactory` - Only factory can call
- ✅ `test_RevertWhen_ConfirmWhenDisputed` - Can't confirm during dispute
- ✅ `test_RevertWhen_OpenDisputeAfterClosed` - Can't dispute closed escrow
- ✅ `test_RevertWhen_ResolveDisputeNotDisputed` - Can't resolve without dispute
- ✅ `test_RevertWhen_ResolveDisputeInvalidWinner` - Winner must be buyer/seller

### E2E.t.sol (6 tests)

**Integration Tests:**

- ✅ `test_E2E_SuccessfulTransaction` - Full happy path flow
  - Seller lists → Buyer purchases → Both confirm → Payments verified
- ✅ `test_E2E_FullLifecycleWithFees` - Complete fee calculation verification
  - Validates platform fee (3%), per-ticket fees ($1.25/ticket), deposits
- ✅ `test_E2E_DisputeResolvedForBuyer` - Buyer wins dispute
  - Buyer gets refund + deposit + 30% of seller's deposit
- ✅ `test_E2E_DisputeResolvedForSeller` - Seller wins dispute
  - Seller gets deposit + 30% of buyer's deposit, buyer gets ticket refund
- ✅ `test_E2E_MultipleListings` - Concurrent listings
  - Multiple sellers, multiple buyers, simultaneous transactions
- ✅ `test_E2E_SellerCancelsBeforeSale` - Cancellation flow
  - Seller cancels before any buyer, gets deposit back

## Fee Structure (Tested & Verified)

```
Escrow Balance Composition:
- Seller deposit: $50 (50e6)
- Buyer deposit: $50 (50e6)
- Ticket cost: ticketPrice × quantity × 1e6

On Successful Transaction:
- Buyer receives: deposit back (50e6)
- Seller receives: ticketTotal + deposit - platformFee - perTicketFees
- Platform receives: platformFee + perTicketFees

Platform Fees:
- Platform fee: 3% of ticket total
- Per-ticket fee: $1.25 per ticket (125e4)

On Dispute (Winner = Buyer):
- Buyer receives: ticketTotal + deposit + disputeFee
- Platform receives: deposit - disputeFee + platformFee + perTicketFees

On Dispute (Winner = Seller):
- Buyer receives: ticketTotal (refund)
- Seller receives: deposit + disputeFee
- Platform receives: deposit - disputeFee + platformFee + perTicketFees

Dispute Fee: 30% of loser's deposit
```

## Test Patterns

### Modern Foundry Test Pattern

All negative tests use `vm.expectRevert` instead of deprecated `testFail*` pattern:

```solidity
// ✅ Modern pattern
function test_RevertWhen_Condition() public {
    vm.expectRevert("Error message");
    contract.failingFunction();
}

// ❌ Deprecated pattern (removed)
function testFail_Condition() public {
    contract.failingFunction();
}
```

## Key Test Features

1. **MockERC20**: Custom test token mimicking USDC with 6 decimals
2. **Event Testing**: Uses `vm.expectEmit` to verify events
3. **Balance Verification**: Tracks before/after balances for accuracy
4. **Access Control**: Tests all permission checks
5. **State Validation**: Verifies contract state changes
6. **Multi-actor Scenarios**: Tests seller, buyer, owner, resolver interactions

## Gas Usage

Approximate gas costs (from test output):

| Operation            | Gas Cost           |
| -------------------- | ------------------ |
| Deploy Factory       | ~22,000            |
| List Ticket          | ~186,000           |
| Purchase Ticket      | ~1,108,000         |
| Seller Confirm       | ~26,000            |
| Buyer Confirm        | ~51,000            |
| Open Dispute         | ~35,000            |
| Resolve Dispute      | ~101,000 - 129,000 |
| Close Listing        | ~182,000           |
| Full E2E Transaction | ~1,184,000         |

## Test Environment Setup

```solidity
// Test constants
uint256 constant DEPOSIT = 50 * 1e6; // $50
uint256 constant TICKET_PRICE = 100; // $100 (before decimals)
uint256 constant QUANTITY = 2; // 2 tickets
uint256 constant INITIAL_BALANCE = 10_000 * 1e6; // $10,000

// Test actors
address owner = makeAddr("owner");
address seller = makeAddr("seller");
address buyer = makeAddr("buyer");
address resolver = makeAddr("resolver");
```

## Notes

- All tests use Foundry's cheatcodes (`vm.prank`, `vm.startPrank`, `vm.expectRevert`, etc.)
- USDC is mocked with 6 decimals matching mainnet USDC
- All monetary values use `1e6` multiplier for 6-decimal precision
- Tests verify both success and failure paths
- Comprehensive coverage of edge cases and error conditions
