// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/DataStructures.sol";
import "../src/EscrowStorage.sol";
import "../src/MilestoneManager.sol";
import "../src/DisputeResolution.sol";
import "../src/EscrowMarketplace.sol";

contract DeployEscrowMarketplace is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 platformFeeRate = 200;
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Optional: Add tokens for testing - adjust to your needs
        address testToken = address(0x46Ca967e39D13595B71cab6AD69237d13096Eb28);

        vm.startBroadcast(deployerPrivateKey);

        EscrowMarketplace escrowMarketplace = new EscrowMarketplace();

        escrowMarketplace.updatePlatformWallet(deployerAddress);

        escrowMarketplace.updatePlatformFeeRate(platformFeeRate);

        escrowMarketplace.setApprovedToken(testToken, true);

        escrowMarketplace.setDisputeResolver(deployerAddress, true);

        require(!escrowMarketplace.paused(), "Contract should not be paused");

        vm.stopBroadcast();

        console.log("Deployment and configuration complete!");
    }
}
