// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";


contract Escrow {
    // factory contract needed to query addresses to resolve disputes
    address public immutable factory;
    IERC20 internal immutable USDC;
    uint256 public immutable transactionId;
    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable ticketPrice;
    uint256 public immutable quantity;
    address public immutable platformRevenue;
    
    
    uint256 private confirmations;
    bool public disputed = false;
    bool public closed = false;

    uint256 private constant USER_DEPOSIT = 50 * 1e6; // 50 USDC
    uint256 private constant PLATFORM_FEE_PERCENT = 3; // 3% fee
    uint256 private constant PER_TICKET_FEE = 125 * 1e4;
    uint256 private constant DISPUTE_FEE_PERCENT = 30;

    // Move these to factory Contract, will make getting data easier.
    event BuyerAdded(uint256 indexed transactionId);
    event TxConfirmed(uint256 indexed transactionId,  address indexed confirmee);
    event DisputeOpened(uint256 indexed transactionId, address party);
    event DisputeResolved(uint256 indexed transactionId, address winner);

    constructor (
        address usdcAddress, 
        uint256 _transactionId, 
        address _seller, 
        address _buyer,
        uint256 _ticketPrice,
        uint256 _quantity,
        address _platformRevenue
     ) {
        // init Factory Contract here
        USDC = IERC20(usdcAddress);
        factory = msg.sender;
        transactionId = _transactionId;
        seller = _seller;
        buyer = _buyer;
        ticketPrice = _ticketPrice;
        quantity = _quantity;
        platformRevenue = _platformRevenue;

    }


    modifier OnlyFactory() {
        require(msg.sender == factory, "Please use Factory contract to interact with escrow");
        _;
    }

    modifier requireOpen() {
        require(!closed, "Escrow is closed");
        require(!disputed, "Escrow is in dispute");
        _;
    }

    modifier requireDisputed() {
        require(disputed, "Escrow is not in dispute");
        _;
    }


    function PartyConfirmation(address confirmee) external requireOpen OnlyFactory {
        confirmations++;
        emit TxConfirmed(transactionId, confirmee);
        
        if (confirmations >= 2) {
            _releaseFunds();
        }
    }

    function openDispute() external requireOpen OnlyFactory {
        disputed = true;
        emit DisputeOpened(transactionId, tx.origin);
    }

    function resolveDispute(address winner) external requireDisputed OnlyFactory {
        require(winner == buyer || winner == seller, "Invalid recipient");
        require(!closed, "Already closed");
        
        uint256 contractBalance = USDC.balanceOf(address(this));
        uint256 ticketTotal = ticketPrice * quantity * 1e6;
        uint256 expectedBalance = ticketTotal + (USER_DEPOSIT * 2);
        require(contractBalance >= expectedBalance, "Insufficient funds in escrow");
        
        // Platform takes 30% of loser's deposit as dispute fee
        uint256 disputeFee = (USER_DEPOSIT * DISPUTE_FEE_PERCENT) / 100;
        
        if (winner == buyer) {
            // Buyer wins: Gets ticket refund + their deposit + 30% of seller's deposit
            uint256 buyerAmount = ticketTotal + USER_DEPOSIT + disputeFee;
            uint256 platformAmount = contractBalance - buyerAmount;
            
            require(USDC.transfer(buyer, buyerAmount), "Buyer transfer failed");
            require(USDC.transfer(platformRevenue, platformAmount), "Platform transfer failed");
        } else {
            // Seller wins: Gets their deposit + 30% of buyer's deposit
            // Buyer gets: Ticket cost refunded
            uint256 sellerAmount = USER_DEPOSIT + disputeFee;
            uint256 buyerRefund = ticketTotal;
            uint256 platformAmount = contractBalance - sellerAmount - buyerRefund;
            
            require(USDC.transfer(buyer, buyerRefund), "Buyer refund failed");
            require(USDC.transfer(seller, sellerAmount), "Seller transfer failed");
            require(USDC.transfer(platformRevenue, platformAmount), "Platform transfer failed");
        }
        
        closed = true;
        disputed = false;
        emit DisputeResolved(transactionId, winner);
    }
    function _releaseFunds() private {
        uint256 contractBalance = USDC.balanceOf(address(this));
        
        // Calculate ticket total and fees
        uint256 ticketTotal = ticketPrice * quantity * 1e6;
        uint256 platformFee = (ticketTotal * PLATFORM_FEE_PERCENT) / 100;  // 3% of ticket cost only
        uint256 perTicketFees = PER_TICKET_FEE * quantity;  // $1.25 per ticket
        uint256 totalRequired = ticketTotal + (USER_DEPOSIT * 2);
        
        require(contractBalance >= totalRequired, "Insufficient funds in escrow");
        
        // Buyer: Gets deposit back
        uint256 buyerRefund = USER_DEPOSIT;
        
        // Seller: Gets ticket cost + their deposit - platform fee - per-ticket fees  
        uint256 sellerAmount = ticketTotal + USER_DEPOSIT - platformFee - perTicketFees;
        
        // Platform: Gets 3% platform fee + per-ticket fees
        uint256 platformAmount = platformFee + perTicketFees;
        
        // Transfers with return value checks
        require(USDC.transfer(buyer, buyerRefund), "Buyer refund failed");
        require(USDC.transfer(seller, sellerAmount), "Seller payment failed");
        require(USDC.transfer(platformRevenue, platformAmount), "Platform fee failed");
        
        closed = true;
    }
}