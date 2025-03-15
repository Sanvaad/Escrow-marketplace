// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/DataStructures.sol";
import "../src/EscrowMarketplace.sol";
import {MockToken} from "./mocks/MockToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Create a contract to receive ETH
contract TestReceiver {
    // Add a receive function so the contract can accept ETH
    receive() external payable {}
}

contract EscrowMarketplaceTest is Test {
    EscrowMarketplace public escrow;
    MockToken public token;

    // Create receiver contracts for each participant
    TestReceiver public clientReceiver;
    TestReceiver public freelancerReceiver;
    TestReceiver public resolverReceiver;
    TestReceiver public ownerReceiver;

    // Use the receiver contracts as the participant addresses
    address public owner;
    address public client;
    address public freelancer;
    address public disputeResolver;

    uint256 public platformFeeRate = 200; // 2%

    // Add a receive function to the test contract
    receive() external payable {}

    function setUp() public {
        // Deploy receiver contracts for each participant
        clientReceiver = new TestReceiver();
        freelancerReceiver = new TestReceiver();
        resolverReceiver = new TestReceiver();
        ownerReceiver = new TestReceiver();

        // Set addresses
        owner = address(ownerReceiver);
        client = address(clientReceiver);
        freelancer = address(freelancerReceiver);
        disputeResolver = address(resolverReceiver);

        // Deploy mock token
        token = new MockToken();

        // Deploy escrow marketplace
        vm.prank(owner); // Deploy as owner
        escrow = new EscrowMarketplace();

        // Setup accounts with ETH
        vm.deal(client, 100 ether);
        vm.deal(freelancer, 100 ether);
        vm.deal(disputeResolver, 100 ether);
        vm.deal(owner, 100 ether);

        // Setup accounts with tokens
        token.mint(client, 1000 * 10 ** 18);
        token.mint(freelancer, 1000 * 10 ** 18);

        // Configure escrow platform
        vm.prank(owner);
        escrow.updatePlatformWallet(owner);

        vm.prank(owner);
        escrow.updatePlatformFeeRate(platformFeeRate);

        vm.prank(owner);
        escrow.setApprovedToken(address(token), true);

        vm.prank(owner);
        escrow.setDisputeResolver(disputeResolver, true);

        // Label addresses for easier debugging
        vm.label(address(escrow), "EscrowMarketplace");
        vm.label(address(token), "MockToken");
        vm.label(client, "Client");
        vm.label(freelancer, "Freelancer");
        vm.label(disputeResolver, "DisputeResolver");
        vm.label(owner, "Owner");
    }

    // Helper function to create an agreement and milestones
    function _createTestAgreement(DataStructures.PaymentType paymentType) internal returns (uint256) {
        // Switch to client
        vm.startPrank(client);

        // Create agreement
        uint256 agreementId = escrow.createAgreement(
            freelancer,
            "Test Project",
            "This is a test project",
            block.timestamp + 30 days,
            paymentType,
            paymentType == DataStructures.PaymentType.ETH ? address(0) : address(token)
        );

        // Add milestones
        escrow.addMilestone(
            agreementId, "First Milestone", "Initial development phase", 1 ether, block.timestamp + 10 days
        );

        escrow.addMilestone(agreementId, "Second Milestone", "Final delivery", 2 ether, block.timestamp + 20 days);

        vm.stopPrank();

        return agreementId;
    }

    // Helper function to fund an agreement
    function _fundAgreement(uint256 agreementId, DataStructures.PaymentType paymentType) internal {
        vm.startPrank(client);

        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        uint256 totalAmount = agreement.totalAmount;
        uint256 platformFee = (totalAmount * platformFeeRate) / 10000;
        uint256 requiredAmount = totalAmount + platformFee;

        if (paymentType == DataStructures.PaymentType.ETH) {
            escrow.fundAgreement{value: requiredAmount}(agreementId);
        } else {
            token.approve(address(escrow), requiredAmount);
            escrow.fundAgreement(agreementId);
        }

        vm.stopPrank();
    }

    // Test 1: Create, fund and complete an ETH agreement
    function testCompleteAgreementWithETH() public {
        // Create and fund agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ETH);
        _fundAgreement(agreementId, DataStructures.PaymentType.ETH);

        // Freelancer starts and submits first milestone
        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 0);
        escrow.submitMilestoneForReview(agreementId, 0, "Work completed for milestone 1");
        vm.stopPrank();

        // Client approves first milestone
        vm.startPrank(client);
        uint256 freelancerBalanceBefore = freelancer.balance;
        escrow.approveMilestone(agreementId, 0, "Great work!");
        uint256 freelancerBalanceAfter = freelancer.balance;
        vm.stopPrank();

        // Check payment was made
        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, 1 ether);

        // Freelancer starts and submits second milestone
        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 1);
        escrow.submitMilestoneForReview(agreementId, 1, "Work completed for milestone 2");
        vm.stopPrank();

        // Client approves second milestone
        vm.startPrank(client);
        freelancerBalanceBefore = freelancer.balance;
        escrow.approveMilestone(agreementId, 1, "Excellent work!");
        freelancerBalanceAfter = freelancer.balance;
        vm.stopPrank();

        // Check payment was made and agreement is completed
        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, 2 ether);

        // Check agreement state
        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(DataStructures.AgreementState.Completed));
    }

    // Test 2: Create, fund and complete an ERC20 agreement
    function testCompleteAgreementWithERC20() public {
        // Create and fund agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ERC20);
        _fundAgreement(agreementId, DataStructures.PaymentType.ERC20);

        // Freelancer starts and submits first milestone
        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 0);
        escrow.submitMilestoneForReview(agreementId, 0, "Work completed for milestone 1");
        vm.stopPrank();

        // Client approves first milestone
        vm.startPrank(client);
        uint256 freelancerTokensBefore = token.balanceOf(freelancer);
        escrow.approveMilestone(agreementId, 0, "Great work!");
        uint256 freelancerTokensAfter = token.balanceOf(freelancer);
        vm.stopPrank();

        // Check payment was made
        assertEq(freelancerTokensAfter - freelancerTokensBefore, 1 ether);

        // Complete second milestone
        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 1);
        escrow.submitMilestoneForReview(agreementId, 1, "Work completed for milestone 2");
        vm.stopPrank();

        vm.startPrank(client);
        escrow.approveMilestone(agreementId, 1, "Excellent work!");
        vm.stopPrank();

        // Check agreement state
        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(DataStructures.AgreementState.Completed));
    }

    // Test 3: Test dispute resolution
    function testDisputeResolution() public {
        // Create and fund agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ETH);
        _fundAgreement(agreementId, DataStructures.PaymentType.ETH);

        // Freelancer starts milestone
        vm.prank(freelancer);
        escrow.startMilestone(agreementId, 0);

        // Client raises dispute
        vm.prank(client);
        escrow.raiseDispute(agreementId, 0, "Work is not as agreed");

        // Freelancer responds to dispute
        vm.prank(freelancer);
        escrow.respondToDispute(agreementId, 0, "Work is according to specifications");

        // Check agreement state
        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(DataStructures.AgreementState.InDispute));

        // Dispute resolver resolves in favor of freelancer
        vm.startPrank(disputeResolver);
        uint256 freelancerBalanceBefore = freelancer.balance;

        escrow.resolveDispute(
            agreementId,
            0,
            DataStructures.DisputeOutcome.FreelancerWins,
            0, // Client amount
            1 ether, // Freelancer amount
            "After review, work meets the requirements"
        );

        uint256 freelancerBalanceAfter = freelancer.balance;
        vm.stopPrank();

        // Check payment was made
        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, 1 ether);

        // Check milestone state
        DataStructures.MilestoneView memory milestone = escrow.getMilestone(agreementId, 0);
        assertEq(uint8(milestone.state), uint8(DataStructures.MilestoneState.Completed));

        // Agreement should be back to InProgress state
        agreement = escrow.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(DataStructures.AgreementState.InProgress));
    }

    // Test 4: Test cancel agreement
    function testCancelAgreement() public {
        // Create and fund agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ETH);
        _fundAgreement(agreementId, DataStructures.PaymentType.ETH);

        // Client cancels agreement
        vm.startPrank(client);
        uint256 clientBalanceBefore = client.balance;
        escrow.cancelAgreement(agreementId);
        uint256 clientBalanceAfter = client.balance;
        vm.stopPrank();

        // Check refund was made
        assertGt(clientBalanceAfter, clientBalanceBefore);

        // Check agreement state
        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(DataStructures.AgreementState.Cancelled));
    }

    // Test 5: Freelancer rating and reputation
    function testRatingAndReputation() public {
        // Create, fund and complete an agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ETH);
        _fundAgreement(agreementId, DataStructures.PaymentType.ETH);

        // Complete both milestones
        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 0);
        escrow.submitMilestoneForReview(agreementId, 0, "Work completed");
        vm.stopPrank();

        vm.prank(client);
        escrow.approveMilestone(agreementId, 0, "Great!");

        vm.startPrank(freelancer);
        escrow.startMilestone(agreementId, 1);
        escrow.submitMilestoneForReview(agreementId, 1, "Work completed");
        vm.stopPrank();

        vm.prank(client);
        escrow.approveMilestone(agreementId, 1, "Excellent!");

        // Rate the freelancer
        vm.prank(client);
        escrow.rateParticipant(agreementId, 5); // 5-star rating

        // Rate the client
        vm.prank(freelancer);
        escrow.rateParticipant(agreementId, 4); // 4-star rating

        // Check ratings
        DataStructures.AgreementView memory agreement = escrow.getAgreement(agreementId);
        assertEq(agreement.freelancerRating, 5);
        assertEq(agreement.clientRating, 4);

        // Check reputation score
        (uint256 freelancerScore, uint256 freelancerJobs) = escrow.getUserReputation(freelancer);
        assertEq(freelancerJobs, 1);
        assertEq(freelancerScore, 5);
    }

    // Test 6: Emergency withdrawal
    function testEmergencyWithdrawal() public {
        // Create and fund agreement
        uint256 agreementId = _createTestAgreement(DataStructures.PaymentType.ETH);
        _fundAgreement(agreementId, DataStructures.PaymentType.ETH);

        // Call emergency withdraw
        vm.prank(owner);
        uint256 ownerBalanceBefore = owner.balance;
        escrow.emergencyWithdraw(address(0)); // ETH withdrawal
        uint256 ownerBalanceAfter = owner.balance;

        // Check withdrawal was successful
        assertGt(ownerBalanceAfter, ownerBalanceBefore);

        // Check contract balance is empty
        assertEq(address(escrow).balance, 0);
    }

    // Test 7: Test pause/unpause
    function testPauseUnpause() public {
        // Pause the contract
        vm.prank(owner);
        escrow.setPaused(true);

        // Try to create an agreement
        vm.startPrank(client);
        vm.expectRevert("Contract is paused");
        escrow.createAgreement(
            freelancer,
            "Test Project",
            "This is a test project",
            block.timestamp + 30 days,
            DataStructures.PaymentType.ETH,
            address(0)
        );
        vm.stopPrank();

        // Unpause the contract
        vm.prank(owner);
        escrow.setPaused(false);

        // Now creation should work
        vm.prank(client);
        uint256 agreementId = escrow.createAgreement(
            freelancer,
            "Test Project",
            "This is a test project",
            block.timestamp + 30 days,
            DataStructures.PaymentType.ETH,
            address(0)
        );

        assertGt(agreementId, 0);
    }
}
