// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TicketFactory} from "../src/Factory.sol";
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

contract FactoryUnitTest is Test {
    TicketFactory public factory;
    MockERC20 public usdc;
    
    address public owner = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public resolver = address(4);
    
    uint256 constant DEPOSIT = 50 * 1e6;
    uint256 constant TICKET_PRICE = 100; // $100
    uint256 constant QUANTITY = 2;
    
    event TicketListed(uint256 indexed transactionId, TicketFactory.TicketPost post);
    event ResolverAdded(address indexed resolver);
    event ResolverRemoved(address indexed resolver);
    
    function setUp() public {
        usdc = new MockERC20();
        
        vm.prank(owner);
        factory = new TicketFactory(owner, address(usdc));
        
        // Mint USDC to test accounts
        usdc.mint(seller, 1000 * 1e6);
        usdc.mint(buyer, 1000 * 1e6);
    }
    
    function test_Constructor() public view {
        assertEq(factory.owner(), owner);
        assertEq(address(factory.USDC()), address(usdc));
        assertEq(factory.transactionCounter(), 0);
        assertTrue(factory.opened());
        assertTrue(factory.isResolver(owner)); // Owner should be resolver
    }
    
    function test_ListTicket() public {
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        
        vm.expectEmit(true, true, true, true);
emit TicketListed(0, TicketFactory.TicketPost({
            transactionId: 0,
            costAmount: TICKET_PRICE,
            quantity: QUANTITY,
            seller: seller,
            buyer: address(0),
            sellerConfirmed: false,
            buyerConfirmed: false,
            disputed: false,
            description: "Test ticket",
            closed: false,
            escrowAddress: address(0)
        }));
        
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        vm.stopPrank();
        
        (uint256 txId, uint256 cost, uint256 qty, address sellerAddr,,,,,, , ) = factory.Posts(0);
        assertEq(txId, 0);
        assertEq(cost, TICKET_PRICE);
        assertEq(qty, QUANTITY);
        assertEq(sellerAddr, seller);
        assertEq(usdc.balanceOf(address(factory)), DEPOSIT);
    }
    
    function test_RevertWhen_ListTicketWithoutDeposit() public {
        vm.prank(seller);
        // No approval
        vm.expectRevert();
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
    }
    
    function test_RevertWhen_ListTicketZeroPrice() public {
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        vm.expectRevert("Cost must be greater than 0");
        factory.listTicket(0, QUANTITY, "Test ticket");
        vm.stopPrank();
    }
    
    function test_RevertWhen_ListTicketZeroQuantity() public {
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        vm.expectRevert("Quantity must be greater than 0");
        factory.listTicket(TICKET_PRICE, 0, "Test ticket");
        vm.stopPrank();
    }
    
    function test_PurchaseTicket() public {
        // Seller lists ticket
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        vm.stopPrank();
        
        // Buyer purchases
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        (,,,, address buyerAddr,,,, , , address escrowAddr) = factory.Posts(0);
        assertEq(buyerAddr, buyer);
        assertTrue(escrowAddr != address(0));
        
        // Check escrow has both deposits
        uint256 expectedEscrowBalance = (DEPOSIT * 2) + (TICKET_PRICE * QUANTITY * 1e6);
        assertEq(usdc.balanceOf(escrowAddr), expectedEscrowBalance);
    }
    
    function test_RevertWhen_PurchaseOwnTicket() public {
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        usdc.approve(address(factory), buyerPayment);
        vm.expectRevert("Cannot buy your own ticket");
        factory.purchaseTicket(0); // Should fail - can't buy own ticket
        vm.stopPrank();
    }
    
    function test_CloseListing() public {
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        
        uint256 balanceBefore = usdc.balanceOf(seller);
        factory.closeListing(0);
        uint256 balanceAfter = usdc.balanceOf(seller);
        vm.stopPrank();
        
        assertEq(balanceAfter - balanceBefore, DEPOSIT);
        (,,,,,,, , , bool closed, ) = factory.Posts(0);
        assertTrue(closed);
    }
    
    function test_RevertWhen_CloseListingWithBuyer() public {
        // List and purchase
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        vm.stopPrank();
        
        vm.startPrank(buyer);
        uint256 buyerPayment = DEPOSIT + (TICKET_PRICE * QUANTITY * 1e6);
        usdc.approve(address(factory), buyerPayment);
        factory.purchaseTicket(0);
        vm.stopPrank();
        
        // Should fail - buyer exists
        vm.prank(seller);
        vm.expectRevert("Cannot close - buyer exists");
        factory.closeListing(0);
    }
    
    function test_AddResolver() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ResolverAdded(resolver);
        factory.addResolver(resolver);
        
        assertTrue(factory.isResolver(resolver));
        address[] memory resolvers = factory.getResolvers();
        assertEq(resolvers.length, 2); // Owner + new resolver
    }
    
    function test_RevertWhen_AddResolverNotOwner() public {
        vm.prank(seller);
        vm.expectRevert();
        factory.addResolver(resolver);
    }
    
    function test_RemoveResolver() public {
        vm.startPrank(owner);
        factory.addResolver(resolver);
        assertTrue(factory.isResolver(resolver));
        
        vm.expectEmit(true, false, false, false);
        emit ResolverRemoved(resolver);
        factory.removeResolver(resolver);
        vm.stopPrank();
        
        assertFalse(factory.isResolver(resolver));
    }
    
    function test_RevertWhen_RemoveOwnerAsResolver() public {
        vm.prank(owner);
        vm.expectRevert("Cannot remove owner as resolver");
        factory.removeResolver(owner); // Should fail
    }
    
    function test_CloseFactory() public {
        vm.prank(owner);
        factory.closeFactory();
        assertFalse(factory.opened());
    }
    
    function test_RevertWhen_ListTicketWhenClosed() public {
        vm.prank(owner);
        factory.closeFactory();
        
        vm.startPrank(seller);
        usdc.approve(address(factory), DEPOSIT);
        vm.expectRevert("Factory is closed");
        factory.listTicket(TICKET_PRICE, QUANTITY, "Test ticket");
        vm.stopPrank();
    }
}
