// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/Lottery.sol";

contract DeployRegistry is Script {
    function run() external {
        // set up deployer
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(privKey);

        // set up a test account
        uint256 testPrivKey = vm.envUint("TEST_PRIVATE_KEY");
        address testAccount = vm.rememberKey(testPrivKey);

        // log deployer data
        console2.log("Deployer: ", deployer);
        console2.log("Deployer Nonce: ", vm.getNonce(deployer));

        // log test account data
        console2.log("Test Account: ", testAccount);
        console2.log("Test Account Nonce: ", vm.getNonce(testAccount));

        vm.startBroadcast(deployer);

        //first deploy the Lottery contract
        Lottery lottery = new Lottery();

        //proceed to create a lottery
        uint256 roundID = lottery.createLottery();

        vm.stopBroadcast();

        //then, we will spin up 1 account to buy tickets
        vm.startBroadcast(testAccount);

        //then, buy a ticket
        lottery.buyTicket(roundID);

        vm.stopBroadcast();

        //log the addresses of the deployed contracts
        console2.log("Lottery Address: ", address(lottery));
        console2.log("Lottery Round ID: ", roundID);
        console2.log("Ticket Price: ", lottery.ticketPrice());
    }
}
