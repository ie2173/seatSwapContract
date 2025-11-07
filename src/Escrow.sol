// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";


contract Escrow {
    // factory contract needed to query addresses to resolve disputes
    address public immutable owner;
    IERC20 internal immutable USDC;
    uint256 public immutable transactionId;
    address public immutable buyer;
    address public immutable seller;
    uint256 private balance = USDC.balanceOf(address(this));
    uint256 private totalVotes;
    bool public disputed = false;
    bool public closed = false;

    // Move these to factory Contract, will make getting data easier.
    event BuyerConfirmed(uint256 indexed transactionId);
    event SellerConfirmed(uint256 indexed transactionId);
    event BuyerCancelled(uint256 indexed transactionId);
    event SellerCancelled(uint256 indexed transactionId);
    event DisputeOpened(uint256 indexed transactionId, address indexed openedBy);
    event FundsReleased(uint256 indexed transactionId, address indexed buyer, address indexed seller, uint256 amount);

    constructor (address _usdc, uint256 _transactionId,address _buyer, address _seller, uint256 _amount) {
        // init Factory Contract here
        USDC = IERC20(_usdc);
        transactionId = _transactionId;
        buyer = _buyer;
        seller = _seller;

        USDC.transferFrom(buyer, address(this), _amount);
    }


modifier OnlyFactory() {
    require(msg.sender == owner, "Please use Factory contract to interact with escrow");
    _;
}

modifier requireOpen() {
    require(!closed, "Escrow is closed");
    _;
}



function PartyConfirmation() external requireOpen OnlyFactory {
    
    totalVotes += 1;
    if (totalVotes >= 2) {
        USDC.transfer(seller, USDC.balanceOf(address(this)));
        closed = true;
    }
}

function openDispute() external requireOpen OnlyFactory {
    disputed = true;
}

function resolveDispute(address to, uint256 amount) external OnlyFactory {
    require(disputed, "No dispute to resolve");
    require(to == buyer || to == seller, "Invalid recipient");
    USDC.transfer(to, amount);
}

}