// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function totalSupply() external pure returns (uint256) { return 0; }
    function decimals() external pure returns (uint8) { return 6; }
    function symbol() external pure returns (string memory) { return "MUSDC"; }
    function name() external pure returns (string memory) { return "Mock USDC"; }
}

contract EscrowUnitTest is Test {
    Escrow public escrow;
    MockERC20 public usdc;
    
    address public factory = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public platformRevenue = address(4);
    
    uint256 constant TX_ID = 1;
    uint256 constant TICKET_PRICE = 100; // $100
    uint256 constant QUANTITY = 2;
    uint256 constant DEPOSIT = 50 * 1e6;
    
    function setUp() public {
        usdc = new MockERC20();
        
        vm.prank(factory);
        escrow = new Escrow(
            address(usdc),
            TX_ID,
            seller,
            buyer,
            TICKET_PRICE,
            QUANTITY,
            platformRevenue
        );
        
        // Fund escrow with both deposits and ticket cost
        uint256 totalAmount = (DEPOSIT * 2) + (TICKET_PRICE * QUANTITY * 1e6);
        usdc.mint(address(escrow), totalAmount);
    }
    
    function test_Constructor() public view {
        assertEq(escrow.factory(), factory);
        assertEq(escrow.transactionId(), TX_ID);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.ticketPrice(), TICKET_PRICE);
        assertEq(escrow.quantity(), QUANTITY);
        assertEq(escrow.platformRevenue(), platformRevenue);
        assertFalse(escrow.disputed());
        assertFalse(escrow.closed());
    }
    
    function test_PartyConfirmation() public {
        // First confirmation
        vm.prank(factory);
        escrow.PartyConfirmation();
        assertFalse(escrow.closed()); // Not closed yet
        
        // Second confirmation - should release funds
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 platformBalanceBefore = usdc.balanceOf(platformRevenue);
        
        vm.prank(factory);
        escrow.PartyConfirmation();
        
        assertTrue(escrow.closed());
        
        // Check payments
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 platformFee = (ticketTotal * 3) / 100; // 3%
        uint256 perTicketFees = (125 * 1e4) * QUANTITY; // $1.25 per ticket
        
        uint256 buyerRefund = DEPOSIT;
        uint256 sellerAmount = ticketTotal + DEPOSIT - platformFee - perTicketFees;
        uint256 platformAmount = platformFee + perTicketFees;
        
        assertEq(usdc.balanceOf(buyer) - buyerBalanceBefore, buyerRefund);
        assertEq(usdc.balanceOf(seller) - sellerBalanceBefore, sellerAmount);
        assertEq(usdc.balanceOf(platformRevenue) - platformBalanceBefore, platformAmount);
    }
    
    function test_RevertWhen_PartyConfirmationNotFactory() public {
        vm.prank(buyer);
        vm.expectRevert("Please use Factory contract to interact with escrow");
        escrow.PartyConfirmation(); // Should fail - not factory
    }
    
    function test_OpenDispute() public {
        vm.prank(factory);
        escrow.openDispute();
        
        assertTrue(escrow.disputed());
    }
    
    function test_RevertWhen_OpenDisputeAfterClosed() public {
        // Close escrow
        vm.startPrank(factory);
        escrow.PartyConfirmation();
        escrow.PartyConfirmation();
        
        // Try to open dispute
        vm.expectRevert("Escrow is closed");
        escrow.openDispute(); // Should fail
        vm.stopPrank();
    }
    
    function test_ResolveDisputeBuyerWins() public {
        // Open dispute
        vm.startPrank(factory);
        escrow.openDispute();
        
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 platformBalanceBefore = usdc.balanceOf(platformRevenue);
        
        // Buyer wins
        escrow.resolveDispute(buyer);
        vm.stopPrank();
        
        assertTrue(escrow.closed());
        assertFalse(escrow.disputed());
        
        // Buyer gets: ticket refund + deposit + 30% of seller's deposit
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 disputeFee = (DEPOSIT * 30) / 100;
        uint256 expectedBuyerAmount = ticketTotal + DEPOSIT + disputeFee;
        
        assertEq(usdc.balanceOf(buyer) - buyerBalanceBefore, expectedBuyerAmount);
        assertTrue(usdc.balanceOf(platformRevenue) > platformBalanceBefore);
    }
    
    function test_ResolveDisputeSellerWins() public {
        // Open dispute
        vm.startPrank(factory);
        escrow.openDispute();
        
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 platformBalanceBefore = usdc.balanceOf(platformRevenue);
        
        // Seller wins
        escrow.resolveDispute(seller);
        vm.stopPrank();
        
        assertTrue(escrow.closed());
        assertFalse(escrow.disputed());
        
        // Seller gets: deposit + 30% of buyer's deposit
        uint256 disputeFee = (DEPOSIT * 30) / 100;
        uint256 expectedSellerAmount = DEPOSIT + disputeFee;
        
        // Buyer gets: ticket refund
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        
        assertEq(usdc.balanceOf(seller) - sellerBalanceBefore, expectedSellerAmount);
        assertEq(usdc.balanceOf(buyer) - buyerBalanceBefore, ticketTotal);
        assertTrue(usdc.balanceOf(platformRevenue) > platformBalanceBefore);
    }
    
    function test_RevertWhen_ResolveDisputeNotDisputed() public {
        vm.prank(factory);
        vm.expectRevert("Escrow is not in dispute");
        escrow.resolveDispute(buyer); // Should fail - not disputed
    }
    
    function test_RevertWhen_ResolveDisputeInvalidWinner() public {
        vm.startPrank(factory);
        escrow.openDispute();
        vm.expectRevert("Invalid recipient");
        escrow.resolveDispute(address(999)); // Should fail - invalid address
        vm.stopPrank();
    }
    
    function test_RevertWhen_ConfirmWhenDisputed() public {
        vm.startPrank(factory);
        escrow.openDispute();
        vm.expectRevert("Escrow is in dispute");
        escrow.PartyConfirmation(); // Should fail - disputed
        vm.stopPrank();
    }
}
