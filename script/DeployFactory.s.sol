// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {TicketFactory} from "../src/Factory.sol";
import {console} from "forge-std/console.sol";

contract DeployFactory is Script {
    TicketFactory public factory;

    function setUp() public {}

    function run() public {
        // Get USDC address from environment (or use default for Sepolia)
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0xAF33ADd7918F685B2A82C1077bd8c07d220FFA04));
        
        console.log("=================================");
        console.log("Deploying TicketFactory...");
        console.log("USDC Address:", usdcAddress);
        console.log("=================================");
        
        // Start broadcast - will use --account flag or PRIVATE_KEY env var
        vm.startBroadcast();

        // Deploy Factory with msg.sender as initial owner
        factory = new TicketFactory(msg.sender, usdcAddress);

        vm.stopBroadcast();
        
        console.log("");
        console.log("=================================");
        console.log("Deployment Successful!");
        console.log("=================================");
        console.log("TicketFactory:", address(factory));
        console.log("Owner:", factory.owner());
        console.log("USDC:", address(factory.USDC()));
        console.log("Transaction Counter:", factory.transactionCounter());
        console.log("=================================");
    }
}
