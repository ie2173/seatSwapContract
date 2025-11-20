// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TicketFactory} from "../src/Factory.sol";
import {Escrow} from "../src/Escrow.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";

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

contract E2ETest is Test {
    TicketFactory public factory;
    MockERC20 public usdc;
    
    address public owner = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public resolver = address(4);
    
    uint256 constant DEPOSIT = 50 * 1e6;
    uint256 constant TICKET_PRICE = 100;
    uint256 constant QUANTITY = 2;
    
    function setUp() public {
        usdc = new MockERC20();
        
        vm.prank(owner);
        factory = new TicketFactory(owner, address(usdc));
        
        // Fund accounts
        usdc.mint(seller, 10000 * 1e6);
        usdc.mint(buyer, 10000 * 1e6);
    }
    
    function test_E2E_SuccessfulTransaction() public {
        console.log("=== E2E: Successful Transaction ===");
        
        // 1. Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        console.log("1. Seller listed ticket");
        
        uint256 sellerInitialBalance = usdc.balanceOf(seller);
        uint256 buyerInitialBalance = usdc.balanceOf(buyer);
        uint256 platformInitialBalance = usdc.balanceOf(owner);
        
        // 2. Buyer purchases ticket
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        console.log("2. Buyer purchased ticket");
        
        // Get escrow address
        (,,,,,,,, , , address escrowAddr) = factory.Posts(0);
        Escrow escrow = Escrow(escrowAddr);
        
        // 3. Seller confirms
        vm.prank(seller);
        factory.sellerConfirm(0);
        console.log("3. Seller confirmed");
        
        // 4. Buyer confirms - triggers payment
        vm.prank(buyer);
        factory.buyerConfirm(0);
        console.log("4. Buyer confirmed");
        
        // Verify escrow is closed
        assertTrue(escrow.closed());
        
        // Verify payments
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 platformFee = (ticketTotal * 3) / 100;
        uint256 perTicketFees = (125 * 1e4) * QUANTITY;
        
        uint256 sellerExpected = sellerInitialBalance + ticketTotal + DEPOSIT - platformFee - perTicketFees;
        uint256 buyerExpected = buyerInitialBalance - ticketTotal;
        uint256 platformExpected = platformInitialBalance + platformFee + perTicketFees;
        
        assertEq(usdc.balanceOf(seller), sellerExpected);
        assertEq(usdc.balanceOf(buyer), buyerExpected);
        assertEq(usdc.balanceOf(owner), platformExpected);
        
        console.log("5. All payments verified!");
    }
    
    function test_E2E_DisputeResolvedForBuyer() public {
        console.log("=== E2E: Dispute Resolved for Buyer ===");
        
        // Setup transaction
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        uint256 buyerInitialBalance = usdc.balanceOf(buyer);
        uint256 platformInitialBalance = usdc.balanceOf(owner);
        
        // Open dispute
        vm.prank(buyer);
        factory.createDispute(0);
        console.log("1. Buyer opened dispute");
        
        // Add resolver and resolve
        vm.startPrank(owner);
        factory.addResolver(resolver);
        vm.stopPrank();
        
        vm.prank(resolver);
        factory.resolveDispute(0, buyer);
        console.log("2. Resolver sided with buyer");
        
        // Get escrow
        (,,,,,,,, , , address escrowAddr) = factory.Posts(0);
        Escrow escrow = Escrow(escrowAddr);
        assertTrue(escrow.closed());
        
        // Verify buyer got refund + deposit + 30% of seller's deposit
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 disputeFee = (DEPOSIT * 30) / 100;
        uint256 expectedBuyerGain = ticketTotal + DEPOSIT + disputeFee;
        
        assertEq(usdc.balanceOf(buyer), buyerInitialBalance + expectedBuyerGain);
        assertTrue(usdc.balanceOf(owner) > platformInitialBalance);
        
        console.log("3. Buyer received full refund + compensation!");
    }
    
    function test_E2E_DisputeResolvedForSeller() public {
        console.log("=== E2E: Dispute Resolved for Seller ===");
        
        // Setup transaction
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        vm.stopPrank();
        
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        uint256 sellerInitialBalance = usdc.balanceOf(seller);
        uint256 buyerInitialBalance = usdc.balanceOf(buyer);
        
        // Open dispute
        vm.prank(seller);
        factory.createDispute(0);
        console.log("1. Seller opened dispute");
        
        // Resolve for seller
        vm.prank(owner);
        factory.resolveDispute(0, seller);
        console.log("2. Owner sided with seller");
        
        // Verify payments
        uint256 disputeFee = (DEPOSIT * 30) / 100;
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        
        assertEq(usdc.balanceOf(seller), sellerInitialBalance + DEPOSIT + disputeFee);
        assertEq(usdc.balanceOf(buyer), buyerInitialBalance + ticketTotal);
        
        console.log("3. Seller kept deposit + compensation, buyer got tickets refunded!");
    }
    
    function test_E2E_MultipleListings() public {
        console.log("=== E2E: Multiple Concurrent Listings ===");
        
        address seller2 = address(5);
        address buyer2 = address(6);
        usdc.mint(seller2, 1000 * 1e6);
        usdc.mint(buyer2, 1000 * 1e6);
        
        // Create 3 listings
        for (uint256 i = 0; i < 3; i++) {
            address currentSeller = i == 0 ? seller : seller2;
            vm.startPrank(currentSeller);
            usdc.approve(address(factory), DEPOSIT);
            factory.listTicket(TICKET_PRICE + (i * 10), QUANTITY, "Ticket listing");
            vm.stopPrank();
        }
        
        assertEq(factory.transactionCounter(), 3);
        console.log("1. Created 3 listings");
        
        // First buyer purchases listing 0
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        console.log("2. Buyer 1 purchased listing 0");
        
        // Second buyer purchases listing 1
        uint256 buyer2Payment = DEPOSIT + ((TICKET_PRICE + 10) * QUANTITY * 1e6);
        vm.startPrank(buyer2);
        usdc.approve(address(factory), buyer2Payment);
        factory.purchaseTicket(1);
        vm.stopPrank();
        console.log("3. Buyer 2 purchased listing 1");
        
        // Verify both transactions
        (,,,, address buyer1Addr,,,,,, ) = factory.Posts(0);
        (,,,, address buyer2Addr,,,,,, ) = factory.Posts(1);
        assertEq(buyer1Addr, buyer);
        assertEq(buyer2Addr, buyer2);
        
        console.log("4. Multiple transactions working correctly!");
    }
    
    function test_E2E_SellerCancelsBeforeSale() public {
        console.log("=== E2E: Seller Cancels Listing ===");
        
        // List ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Concert tickets");
        
        uint256 balanceBefore = usdc.balanceOf(seller);
        
        // Cancel listing
        factory.closeListing(0);
        vm.stopPrank();
        
        uint256 balanceAfter = usdc.balanceOf(seller);
        assertEq(balanceAfter, balanceBefore + DEPOSIT);
        
        (,,,,,,, , , bool closed, ) = factory.Posts(0);
        assertTrue(closed);
        
        console.log("Seller successfully cancelled and got deposit back!");
    }
    
    function test_E2E_FullLifecycleWithFees() public {
        console.log("=== E2E: Full Lifecycle Fee Verification ===");
        
        uint256 sellerStart = usdc.balanceOf(seller);
        uint256 buyerStart = usdc.balanceOf(buyer);
        uint256 platformStart = usdc.balanceOf(owner);
        
        // List
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Tickets");
        vm.stopPrank();
        
        // Purchase
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // Confirm
        vm.prank(seller);
        factory.sellerConfirm(0);
        vm.prank(buyer);
        factory.buyerConfirm(0);
        
        // Calculate expected amounts
        uint256 ticketTotal = TICKET_PRICE * QUANTITY * 1e6;
        uint256 platformFee = (ticketTotal * 3) / 100; // 3%
        uint256 perTicketFees = (125 * 1e4) * QUANTITY; // $1.25 * 2
        
        uint256 sellerNetGain = ticketTotal - platformFee - perTicketFees;
        uint256 buyerNetLoss = ticketTotal;
        uint256 platformNetGain = platformFee + perTicketFees;
        
        assertEq(usdc.balanceOf(seller), sellerStart + sellerNetGain);
        assertEq(usdc.balanceOf(buyer), buyerStart - buyerNetLoss);
        assertEq(usdc.balanceOf(owner), platformStart + platformNetGain);
        
        console.log("Seller net gain:", sellerNetGain);
        console.log("Buyer net loss:", buyerNetLoss);
        console.log("Platform fee:", platformNetGain);
        console.log("All fees calculated correctly!");
    }
}
