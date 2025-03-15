// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EscrowStorage.sol";

/**
 * @title DisputeResolution
 * @dev Handles dispute creation and resolution
 */
abstract contract DisputeResolution is EscrowStorage, ReentrancyGuard {
    // ================ Dispute Management Functions ================

    /**
     * @dev Raise a dispute for a milestone
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _reason Reason for the dispute
     */
    function raiseDispute(uint256 _agreementId, uint256 _milestoneId, string memory _reason)
        external
        onlyParticipant(_agreementId)
        agreementExists(_agreementId)
        notPaused
    {
        Agreement storage agreement = agreements[_agreementId];
        require(
            agreement.state == AgreementState.InProgress || agreement.state == AgreementState.Funded,
            "Agreement must be in progress or funded"
        );

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(!milestone.dispute.isDisputed, "Dispute already raised");
        require(
            milestone.state != MilestoneState.Completed && milestone.state != MilestoneState.Cancelled,
            "Cannot dispute completed or cancelled milestones"
        );

        // Mark as disputed
        milestone.state = MilestoneState.Disputed;
        milestone.dispute.isDisputed = true;
        milestone.dispute.createdAt = block.timestamp;

        // Store dispute reason based on who raised it
        if (msg.sender == agreement.client) {
            milestone.dispute.clientReason = _reason;
        } else {
            milestone.dispute.freelancerResponse = _reason;
        }

        // Update agreement state
        agreement.state = AgreementState.InDispute;

        emit DisputeRaised(_agreementId, _milestoneId, msg.sender);
    }

    /**
     * @dev Respond to a dispute
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _response Response to the dispute
     */
    function respondToDispute(uint256 _agreementId, uint256 _milestoneId, string memory _response)
        external
        onlyParticipant(_agreementId)
        agreementExists(_agreementId)
        notPaused
    {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.InDispute, "Agreement not in dispute");

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.dispute.isDisputed, "No active dispute for this milestone");

        // Store response based on who is responding
        if (msg.sender == agreement.client) {
            require(bytes(milestone.dispute.clientReason).length == 0, "Client already provided reason");
            milestone.dispute.clientReason = _response;
        } else {
            require(bytes(milestone.dispute.freelancerResponse).length == 0, "Freelancer already responded");
            milestone.dispute.freelancerResponse = _response;
        }
    }

    /**
     * @dev Resolve a dispute (by dispute resolver)
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _outcome Outcome of the dispute resolution
     * @param _clientAmount Amount to be paid to client (for compromise)
     * @param _freelancerAmount Amount to be paid to freelancer (for compromise)
     * @param _notes Resolver notes
     */
    function resolveDispute(
        uint256 _agreementId,
        uint256 _milestoneId,
        DisputeOutcome _outcome,
        uint256 _clientAmount,
        uint256 _freelancerAmount,
        string memory _notes
    ) external onlyDisputeResolver agreementExists(_agreementId) notPaused nonReentrant {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.InDispute, "Agreement not in dispute");

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.dispute.isDisputed, "No active dispute for this milestone");
        require(milestone.dispute.outcome == DisputeOutcome.None, "Dispute already resolved");

        // Update dispute details
        milestone.dispute.outcome = _outcome;
        milestone.dispute.resolverNotes = _notes;
        milestone.dispute.resolvedAt = block.timestamp;

        // Process based on outcome
        if (_outcome == DisputeOutcome.ClientWins) {
            // Client gets full refund for the milestone
            milestone.dispute.clientAmount = milestone.amount;
            milestone.dispute.freelancerAmount = 0;

            processDisputePayment(agreement, milestone.amount, 0, agreement.client, agreement.freelancer);

            milestone.state = MilestoneState.Cancelled;
        } else if (_outcome == DisputeOutcome.FreelancerWins) {
            // Freelancer gets full payment
            milestone.dispute.clientAmount = 0;
            milestone.dispute.freelancerAmount = milestone.amount;

            processDisputePayment(agreement, 0, milestone.amount, agreement.client, agreement.freelancer);

            milestone.state = MilestoneState.Completed;
            milestone.completedAt = block.timestamp;
        } else if (_outcome == DisputeOutcome.Compromise) {
            // Split the amount as specified
            require(_clientAmount + _freelancerAmount == milestone.amount, "Sum of amounts must equal milestone amount");

            milestone.dispute.clientAmount = _clientAmount;
            milestone.dispute.freelancerAmount = _freelancerAmount;

            processDisputePayment(agreement, _clientAmount, _freelancerAmount, agreement.client, agreement.freelancer);

            milestone.state = MilestoneState.Completed;
            milestone.completedAt = block.timestamp;
        }

        emit DisputeResolved(
            _agreementId, _milestoneId, _outcome, milestone.dispute.clientAmount, milestone.dispute.freelancerAmount
        );

        // Check if agreement can return to InProgress state
        bool hasActiveDisputes = false;
        for (uint256 i = 0; i < agreement.milestoneCount; i++) {
            if (
                agreement.milestones[i].state == MilestoneState.Disputed
                    && agreement.milestones[i].dispute.outcome == DisputeOutcome.None
            ) {
                hasActiveDisputes = true;
                break;
            }
        }

        // No more disputes, return to InProgress
        if (!hasActiveDisputes) {
            agreement.state = AgreementState.InProgress;
        }

        // Check if all milestones are now completed or cancelled
        bool allSettled = true;
        for (uint256 i = 0; i < agreement.milestoneCount; i++) {
            MilestoneState state = agreement.milestones[i].state;
            if (state != MilestoneState.Completed && state != MilestoneState.Cancelled) {
                allSettled = false;
                break;
            }
        }

        // If all milestones are settled, mark agreement as completed
        if (allSettled) {
            agreement.state = AgreementState.Completed;

            // Transfer remaining platform fee (might have been partially transferred by dispute resolution)
            if (agreement.paymentType == PaymentType.ETH) {
                if (address(this).balance >= agreement.platformFee) {
                    payable(platformWallet).transfer(agreement.platformFee);
                }
            } else {
                IERC20 token = IERC20(agreement.tokenAddress);
                uint256 balance = token.balanceOf(address(this));
                if (balance >= agreement.platformFee) {
                    require(token.transfer(platformWallet, agreement.platformFee), "Token fee transfer failed");
                }
            }

            emit AgreementCompleted(_agreementId);
        }
    }

    /**
     * @dev Process payments for dispute resolution
     */
    function processDisputePayment(
        Agreement storage agreement,
        uint256 clientAmount,
        uint256 freelancerAmount,
        address client,
        address freelancer
    ) private {
        if (agreement.paymentType == PaymentType.ETH) {
            // Transfer ETH
            if (clientAmount > 0) {
                payable(client).transfer(clientAmount);
            }
            if (freelancerAmount > 0) {
                payable(freelancer).transfer(freelancerAmount);
            }
        } else {
            // Transfer ERC20 tokens
            IERC20 token = IERC20(agreement.tokenAddress);
            if (clientAmount > 0) {
                require(token.transfer(client, clientAmount), "Token transfer to client failed");
            }
            if (freelancerAmount > 0) {
                require(token.transfer(freelancer, freelancerAmount), "Token transfer to freelancer failed");
            }
        }
    }
}
