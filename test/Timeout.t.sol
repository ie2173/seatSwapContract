// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {TicketFactory} from "../src/Factory.sol";
import {Escrow} from "../src/Escrow.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _totalSupply += amount;
        _balances[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}

contract TimeoutTest is Test {
    TicketFactory public factory;
    MockERC20 public usdc;
    
    address owner = makeAddr("owner");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");
    
    uint256 constant DEPOSIT = 50 * 1e6; // $50
    uint256 constant TICKET_PRICE = 100; // $100
    uint256 constant QUANTITY = 2; // 2 tickets
    uint256 constant INITIAL_BALANCE = 10_000 * 1e6; // $10,000

    function setUp() public {
        usdc = new MockERC20();
        
        vm.prank(owner);
        factory = new TicketFactory(owner, address(usdc));
        
        // Fund test accounts
        usdc.mint(seller, INITIAL_BALANCE);
        usdc.mint(buyer, INITIAL_BALANCE);
    }

    function test_Timeout_SellerFailsToConfirm() public {
        console.log("=== Timeout: Seller Fails to Confirm ===");
        
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        
        // 3. Fast forward 24 hours + 1 second
        vm.warp(block.timestamp + 24 hours + 1);
        
        // 4. Buyer claims timeout
        vm.prank(buyer);
        factory.claimTimeout(0);
        
        // Verify buyer got refund + seller's deposit
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 expectedPayout = ticketTotal + (DEPOSIT * 2);
        
        assertEq(usdc.balanceOf(buyer) - buyerBalanceBefore, expectedPayout);
        
        // Verify transaction is closed
        (,,,,,,,, , bool closed, ) = factory.Posts(0);
        assertTrue(closed);
        
        console.log("Buyer received full refund + seller's deposit");
    }

    function test_Timeout_BuyerFailsToConfirm() public {
        console.log("=== Timeout: Buyer Fails to Confirm ===");
        
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // 3. Seller confirms
        vm.prank(seller);
        factory.sellerConfirm(0);
        
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 platformBalanceBefore = usdc.balanceOf(owner);
        
        // 4. Fast forward 24 hours + 1 second after seller confirmation
        vm.warp(block.timestamp + 24 hours + 1);
        
        // 5. Seller claims timeout
        vm.prank(seller);
        factory.claimTimeout(0);
        
        // Calculate expected amounts
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 platformFee = (ticketTotal * 3) / 100;
        uint256 perTicketFees = (125 * 1e4) * QUANTITY;
        uint256 expectedSellerPayout = ticketTotal + (DEPOSIT * 2) - platformFee - perTicketFees;
        uint256 expectedPlatformPayout = platformFee + perTicketFees;
        
        assertEq(usdc.balanceOf(seller) - sellerBalanceBefore, expectedSellerPayout);
        assertEq(usdc.balanceOf(owner) - platformBalanceBefore, expectedPlatformPayout);
        
        // Verify transaction is closed
        (,,,,,,,, , bool closed, ) = factory.Posts(0);
        assertTrue(closed);
        
        console.log("Seller received payment + buyer's deposit (minus fees)");
    }

    function test_RevertWhen_ClaimTimeoutTooEarly() public {
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // 3. Try to claim timeout before 24 hours (should fail)
        vm.warp(block.timestamp + 12 hours);
        
        vm.prank(buyer);
        vm.expectRevert("No timeout applicable");
        factory.claimTimeout(0);
    }

    function test_RevertWhen_ClaimTimeoutAfterBothConfirm() public {
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // 3. Seller confirms
        vm.prank(seller);
        factory.sellerConfirm(0);
        
        // 4. Buyer confirms
        vm.prank(buyer);
        factory.buyerConfirm(0);
        
        // 5. Fast forward time
        vm.warp(block.timestamp + 48 hours);
        
        // 6. Try to claim timeout (should fail - already closed)
        vm.prank(buyer);
        vm.expectRevert("Transaction already closed");
        factory.claimTimeout(0);
    }

    function test_RevertWhen_ClaimTimeoutDuringDispute() public {
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // 3. Open dispute
        vm.prank(buyer);
        factory.createDispute(0);
        
        // 4. Fast forward time
        vm.warp(block.timestamp + 48 hours);
        
        // 5. Try to claim timeout (should fail - disputed)
        vm.prank(buyer);
        vm.expectRevert("Cannot claim timeout during dispute");
        factory.claimTimeout(0);
    }

    function test_Timeout_SellerClaimsAtExactDeadline() public {
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        // 2. Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // 3. Seller confirms
        vm.prank(seller);
        factory.sellerConfirm(0);
        
        // 4. Fast forward exactly 24 hours
        vm.warp(block.timestamp + 24 hours);
        
        // 5. Seller claims timeout at exact deadline
        vm.prank(seller);
        factory.claimTimeout(0);
        
        // Verify transaction is closed
        (,,,,,,,, , bool closed, ) = factory.Posts(0);
        assertTrue(closed);
    }
}
