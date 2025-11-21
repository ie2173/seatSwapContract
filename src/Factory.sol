// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { Escrow } from "./Escrow.sol";


contract TicketFactory is Ownable {
// Variables go here
IERC20 public immutable USDC;
uint256 public transactionCounter = 0;
mapping(uint256 => TicketPost) public Posts;
address[] public resolvers;
mapping(address => bool) public isResolver;

bool public opened = true;
struct TicketPost {
    uint256 transactionId;
    uint256 costAmount;
    uint256 quantity;
    address seller;
    address buyer;
    bool sellerConfirmed;
    bool buyerConfirmed;
    bool disputed;
    string description;
    bool closed;
    address escrowAddress;
}
event TicketListed(uint256 indexed transactionId, TicketPost post);
event TicketBid(uint256 indexed transactionId, address EscowAddress);
event ResolverAdded(address indexed resolver);
event ResolverRemoved(address indexed resolver);

    constructor(address initialOwner, address usdcAddress) Ownable(initialOwner) {
        USDC = IERC20(usdcAddress);
        resolvers.push(initialOwner);
        isResolver[initialOwner] = true;
    }

    modifier requireOpen() {
        require(opened, "Factory is closed");
        _;
    }

    modifier onlyResolver() {
        require(isResolver[msg.sender] || msg.sender == owner(), "Not authorized to resolve disputes");
        _;
    }


    function listTicket (uint256 costAmount, uint256 quantity, string memory description) external requireOpen {
        require(costAmount > 0, "Cost must be greater than 0");
        require(quantity > 0, "Quantity must be greater than 0");
        
        Posts[transactionCounter] = TicketPost({
            transactionId: transactionCounter,
            costAmount: costAmount,
            quantity: quantity,
            seller: msg.sender,
            buyer: address(0),
            sellerConfirmed: false,
            buyerConfirmed: false,
            disputed: false,
            description: description,
            closed: false,
            escrowAddress: address(0)
        });
        
        // Seller deposits $50 into factory (will be transferred to escrow when buyer purchases)
        require(USDC.transferFrom(msg.sender, address(this), (50 * 1e6)), "Seller deposit failed");
        
        emit TicketListed(transactionCounter, Posts[transactionCounter]);
        transactionCounter += 1;
    }

    function purchaseTicket(uint256 transactionId) external requireOpen {
        TicketPost storage post = Posts[transactionId];
        require(post.seller != address(0), "Ticket does not exist");
        require(post.buyer == address(0), "Ticket already sold");
        require(!post.closed, "Listing is closed");
        require(msg.sender != post.seller, "Cannot buy your own ticket");
        
        post.buyer = msg.sender;
        
        // Create Escrow contract with all required parameters
        Escrow escrow = new Escrow(
            address(USDC),
            transactionId,
            post.seller,
            msg.sender,
            post.costAmount,
            post.quantity,
            owner()  // platformRevenue = factory owner
        );
        post.escrowAddress = address(escrow);
        
        // Transfer seller's deposit from factory to escrow
        require(USDC.transfer(address(escrow), 50 * 1e6), "Seller deposit transfer failed");
        
        // Transfer buyer's deposit + ticket cost from buyer to escrow
        uint256 buyerAmount = (50 * 1e6) + (post.costAmount * post.quantity * 1e6);
        require(USDC.transferFrom(msg.sender, address(escrow), buyerAmount), "Buyer transfer failed");
        
        emit TicketBid(transactionId, address(escrow));
    }

    function sellerConfirm(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.seller, "Only the seller can confirm");
        require(post.buyer != address(0), "No buyer yet");
        require(!post.sellerConfirmed, "Seller already confirmed");
        require(!post.disputed, "Transaction is disputed");
        require(!post.closed, "Transaction is closed");
        
        post.sellerConfirmed = true;
        
        // Call escrow contract to register confirmation
        Escrow(post.escrowAddress).PartyConfirmation(msg.sender);
    }

    function buyerConfirm(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.buyer, "Only the buyer can confirm");
        require(!post.buyerConfirmed, "Buyer already confirmed");
        require(!post.disputed, "Transaction is disputed");
        require(!post.closed, "Transaction is closed");
        
        post.buyerConfirmed = true;
        
        // Call escrow contract to register confirmation
        Escrow(post.escrowAddress).PartyConfirmation(msg.sender);
        
        // Mark as closed if both parties confirmed
        if (post.sellerConfirmed && post.buyerConfirmed) {
            post.closed = true;
        }
    }

    function closeListing(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(!post.closed, "Listing already closed");
        require(msg.sender == post.seller, "Only the seller can close the listing");
        require(post.buyer == address(0), "Cannot close - buyer exists");
        require(!post.disputed, "Cannot close - disputed");
        
        post.closed = true;
        
        // Refund seller's deposit
        require(USDC.transfer(post.seller, 50 * 1e6), "Refund failed");
    }

    function createDispute(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.seller || msg.sender == post.buyer, "Only buyer or seller can open dispute");
        require(post.buyer != address(0), "No buyer yet");
        require(!post.disputed, "Dispute already opened");
        require(!post.closed, "Transaction already closed");
        
        post.disputed = true;
        
        // Call escrow contract to open dispute
        Escrow(post.escrowAddress).openDispute();
    }

    function resolveDispute(uint256 transactionId, address winner) external onlyResolver {
        TicketPost storage post = Posts[transactionId];
        require(post.disputed, "No dispute to resolve");
        require(winner == post.seller || winner == post.buyer, "Invalid winner");
        
        // Call escrow contract to resolve dispute
        Escrow(post.escrowAddress).resolveDispute(winner);
        
        post.closed = true;
    }

    function displayOpenTickets() external view returns (TicketPost[] memory) {
        TicketPost[] memory openTickets = new TicketPost[](transactionCounter);
        uint256 count = 0;
        for (uint256 i = 0; i < transactionCounter; i++) {
            if (!Posts[i].closed) {
                openTickets[count] = Posts[i];
                count++;
            }
        }
        return openTickets;
    }

    function addResolver(address resolver) external onlyOwner {
        require(resolver != address(0), "Invalid resolver address");
        require(!isResolver[resolver], "Already a resolver");
        
        resolvers.push(resolver);
        isResolver[resolver] = true;
        
        emit ResolverAdded(resolver);
    }

    function removeResolver(address resolver) external onlyOwner {
        require(isResolver[resolver], "Not a resolver");
        require(resolver != owner(), "Cannot remove owner as resolver");
        
        for (uint256 i = 0; i < resolvers.length; i++) {
            if (resolvers[i] == resolver) {
                resolvers[i] = resolvers[resolvers.length - 1];
                resolvers.pop();
                break;
            }
        }
        
        isResolver[resolver] = false;
        
        emit ResolverRemoved(resolver);
    }

    function closeFactory() external onlyOwner {
        opened = false;
    }

    // View function to get all resolvers
    function getResolvers() external view returns (address[] memory) {
        return resolvers;
    }

    // Check if an address is a resolver
    function checkIsResolver(address account) external view returns (bool) {
        return isResolver[account];
    }

// functions
// ✅ Seller List Tickets
// ✅ Buyer Purchase Tickets
// seller confirm delivery
// buyer confirm receipt
// init dispute 
// resolve dispute
// add resolver
// remove resolver
// display open tickets



}