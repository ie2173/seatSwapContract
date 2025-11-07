// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { Escrow } from "./Escrow.sol";


contract TicketFactory is Ownable {
// Variables go here
IERC20 internal immutable USDC;
Escrow internal immutable ESCROW;
address public immutable OWNER;
uint256 public transactionCounter = 0;
mapping(uint256 => TicketPost) public Posts;
address[] public resolvers;

bool public opened = true;
struct TicketPost {
    uint256 transactionId;
    uint256 costAmount;
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

    constructor(address initialOwner, address usdcAddress) Ownable(initialOwner) {
        USDC = IERC20(usdcAddress);
        resolvers.push(initialOwner);
    }

    modifier OnlyOwner() {
        require(msg.sender == OWNER, "Only the owner can perform this action");
        _;
    }

    modifier requireOpen() {
        require(opened, "Factory is closed");
        _;
    }


    function listTicket (uint256 costAmount, string memory description) external requireOpen {
        Posts[transactionCounter] = TicketPost({
            transactionId: transactionCounter,
            costAmount: costAmount,
            seller: msg.sender,
            buyer: address(0),
            sellerConfirmed: false,
            buyerConfirmed: false,
            disputed: false,
            description: description,
            closed: false,
            escrowAddress: address(0)
        });
        emit TicketListed(transactionCounter, Posts[transactionCounter]);
        transactionCounter += 1;
    }

    function purchaseTicket(uint256 transactionId) external requireOpen {
        TicketPost storage post = Posts[transactionId];
        require(post.seller != address(0), "Ticket does not exist");
        require(post.buyer == address(0), "Ticket already sold");
        post.buyer = msg.sender;
        // Create Escrow contract
        Escrow escrow = new Escrow(address(USDC), transactionId, post.seller, post.buyer, post.costAmount);
        post.escrowAddress = address(escrow);
        emit TicketBid(transactionId, address(escrow));
    }

    function sellerConfirm(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.seller, "Only the seller can confirm");
        require(!post.sellerConfirmed, "Seller already confirmed");
        post.sellerConfirmed = true;
        //  add vote to escrow contract
    }

    function buyerConfirm(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.buyer, "Only the buyer can confirm");
        require(!post.buyerConfirmed, "Buyer already confirmed");
        post.buyerConfirmed = true;
        // add vote to escrow contract
    }

    function createDispute(uint256 transactionId) external {
        TicketPost storage post = Posts[transactionId];
        require(msg.sender == post.seller || msg.sender == post.buyer, "Only buyer or seller can open dispute");
        require(!post.disputed, "Dispute already opened");
        post.disputed = true;
        // add dispute logic to escrow contract
    }

    function resolveDispute(uint256 transactionId, address to, uint256 amount) external OnlyOwner {
        TicketPost storage post = Posts[transactionId];
        require(post.disputed, "No dispute to resolve");
        require(to == post.seller || to == post.buyer, "Invalid recipient");
        // add logic to transfer funds from escrow contract
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

    function addResolver(address resolver) external OnlyOwner {
        resolvers.push(resolver);
    }

    function removeResolver(address resolver) external OnlyOwner {
        for (uint256 i = 0; i < resolvers.length; i++) {
            if (resolvers[i] == resolver) {
                resolvers[i] = resolvers[resolvers.length - 1];
                resolvers.pop();
                break;
            }
        }
    }

    function closeFactory() external OnlyOwner {
        opened = false;
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