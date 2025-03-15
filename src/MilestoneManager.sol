// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EscrowStorage.sol";

/**
 * @title MilestoneManager
 * @dev Handles milestone creation, progress and completion
 */
abstract contract MilestoneManager is EscrowStorage, ReentrancyGuard {
    // No local modifiers - using modifiers from EscrowStorage

    // ================ Milestone Management Functions ================

    /**
     * @dev Adds a milestone to an agreement
     * @param _agreementId ID of the agreement
     * @param _title Title of the milestone
     * @param _description Description of the milestone
     * @param _amount Amount allocated for the milestone
     * @param _deadline Optional deadline for this milestone (0 for none)
     */
    function addMilestone(
        uint256 _agreementId,
        string memory _title,
        string memory _description,
        uint256 _amount,
        uint256 _deadline
    ) external onlyClient(_agreementId) agreementExists(_agreementId) notPaused {
        Agreement storage agreement = agreements[_agreementId];

        // Agreement must be in Created state to add milestones
        require(agreement.state == AgreementState.Created, "Can only add milestones to unfunded agreements");

        uint256 milestoneId = agreement.milestoneCount;
        agreement.milestoneCount++;

        Milestone storage newMilestone = agreement.milestones[milestoneId];
        newMilestone.id = milestoneId;
        newMilestone.title = _title;
        newMilestone.description = _description;
        newMilestone.amount = _amount;
        newMilestone.deadline = _deadline;
        newMilestone.state = MilestoneState.NotStarted;

        // Update total amount
        agreement.totalAmount += _amount;

        emit MilestoneCreated(_agreementId, milestoneId, _amount);
    }

    /**
     * @dev Freelancer starts working on a milestone
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     */
    function startMilestone(uint256 _agreementId, uint256 _milestoneId)
        external
        onlyFreelancer(_agreementId)
        agreementExists(_agreementId)
        notPaused
    {
        Agreement storage agreement = agreements[_agreementId];
        require(
            agreement.state == AgreementState.Funded || agreement.state == AgreementState.InProgress,
            "Agreement must be funded to start milestone"
        );

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.state == MilestoneState.NotStarted, "Milestone not in NotStarted state");

        // Check if milestone deadline is in the future if set
        if (milestone.deadline > 0) {
            require(block.timestamp < milestone.deadline, "Milestone deadline has already passed");
        }

        milestone.state = MilestoneState.InProgress;
        milestone.startedAt = block.timestamp;
        agreement.state = AgreementState.InProgress;

        emit MilestoneStarted(_agreementId, _milestoneId);
    }

    /**
     * @dev Freelancer submits a milestone for review
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _feedback Feedback or notes for the client
     */
    function submitMilestoneForReview(uint256 _agreementId, uint256 _milestoneId, string memory _feedback)
        external
        onlyFreelancer(_agreementId)
        agreementExists(_agreementId)
        notPaused
    {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.InProgress, "Agreement not in progress");

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.state == MilestoneState.InProgress, "Milestone not in progress");

        milestone.state = MilestoneState.ReviewRequested;
        milestone.freelancerFeedback = _feedback;
        milestone.submittedAt = block.timestamp;

        emit MilestoneSubmitted(_agreementId, _milestoneId);
    }

    /**
     * @dev Client approves a milestone
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _feedback Optional feedback from client
     */
    function approveMilestone(uint256 _agreementId, uint256 _milestoneId, string memory _feedback)
        external
        onlyClient(_agreementId)
        agreementExists(_agreementId)
        notPaused
        nonReentrant
    {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.InProgress, "Agreement not in progress");

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.state == MilestoneState.ReviewRequested, "Milestone not submitted for review");

        milestone.state = MilestoneState.Approved;
        milestone.clientFeedback = _feedback;

        emit MilestoneApproved(_agreementId, _milestoneId);

        // Release payment
        completeMilestone(_agreementId, _milestoneId);
    }

    /**
     * @dev Client requests revisions to a milestone
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @param _feedback Feedback with revision requests
     */
    function requestRevision(uint256 _agreementId, uint256 _milestoneId, string memory _feedback)
        external
        onlyClient(_agreementId)
        agreementExists(_agreementId)
        notPaused
    {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.InProgress, "Agreement not in progress");

        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");
        Milestone storage milestone = agreement.milestones[_milestoneId];

        require(milestone.state == MilestoneState.ReviewRequested, "Milestone not submitted for review");

        milestone.state = MilestoneState.InProgress;
        milestone.clientFeedback = _feedback;
        milestone.revisionCount++;

        emit MilestoneRevisionRequested(_agreementId, _milestoneId, _feedback);
    }

    /**
     * @dev Internal function to complete a milestone and release payment
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     */
    function completeMilestone(uint256 _agreementId, uint256 _milestoneId) internal {
        Agreement storage agreement = agreements[_agreementId];
        Milestone storage milestone = agreement.milestones[_milestoneId];

        milestone.state = MilestoneState.Completed;
        milestone.completedAt = block.timestamp;

        // Transfer funds based on payment type
        if (agreement.paymentType == PaymentType.ETH) {
            // Transfer ETH to freelancer
            payable(agreement.freelancer).transfer(milestone.amount);
        } else {
            // Transfer ERC20 tokens to freelancer
            IERC20 token = IERC20(agreement.tokenAddress);
            require(token.transfer(agreement.freelancer, milestone.amount), "Token transfer failed");
        }

        emit MilestoneCompleted(_agreementId, _milestoneId, milestone.amount);

        // Check if all milestones are completed
        bool allCompleted = true;
        for (uint256 i = 0; i < agreement.milestoneCount; i++) {
            if (agreement.milestones[i].state != MilestoneState.Completed) {
                allCompleted = false;
                break;
            }
        }

        // If all milestones are completed, mark agreement as completed
        if (allCompleted) {
            agreement.state = AgreementState.Completed;

            // Transfer platform fee
            if (agreement.paymentType == PaymentType.ETH) {
                payable(platformWallet).transfer(agreement.platformFee);
            } else {
                IERC20 token = IERC20(agreement.tokenAddress);
                require(token.transfer(platformWallet, agreement.platformFee), "Token fee transfer failed");
            }

            // Update reputation
            userCompletedJobs[agreement.client]++;
            userCompletedJobs[agreement.freelancer]++;

            emit AgreementCompleted(_agreementId);
        }
    }

    /**
     * @dev Rate the other party after agreement completion
     * @param _agreementId ID of the agreement
     * @param _rating Rating from 1-5
     */
    function rateParticipant(uint256 _agreementId, uint256 _rating)
        external
        onlyParticipant(_agreementId)
        agreementExists(_agreementId)
    {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.state == AgreementState.Completed, "Can only rate after completion");
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");

        address ratedAddress;
        if (msg.sender == agreement.client) {
            require(agreement.freelancerRating == 0, "Freelancer already rated");
            agreement.freelancerRating = _rating;
            ratedAddress = agreement.freelancer;

            // Update freelancer reputation score
            userReputationScore[agreement.freelancer] = (
                userReputationScore[agreement.freelancer] * (userCompletedJobs[agreement.freelancer] - 1) + _rating
            ) / userCompletedJobs[agreement.freelancer];
        } else {
            require(agreement.clientRating == 0, "Client already rated");
            agreement.clientRating = _rating;
            ratedAddress = agreement.client;

            // Update client reputation score
            userReputationScore[agreement.client] = (
                userReputationScore[agreement.client] * (userCompletedJobs[agreement.client] - 1) + _rating
            ) / userCompletedJobs[agreement.client];
        }

        emit UserRated(_agreementId, ratedAddress, _rating);
    }
}
