// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MilestoneManager.sol";
import "./DisputeResolution.sol";

/**
 * @title EscrowMarketplace
 * @dev Main contract for the EscrowMarketplace ecosystem
 */
contract EscrowMarketplace is MilestoneManager, DisputeResolution {
    // ================ Constructor ================
    constructor() MilestoneManager() DisputeResolution() ReentrancyGuard() {}

    // ================ Agreement Management Functions ================

    /**
     * @dev Creates a new agreement between client and freelancer
     * @param _freelancer Address of the freelancer
     * @param _title Title of the agreement
     * @param _description Description of the agreement
     * @param _deadline Optional deadline for completion (0 for none)
     * @param _paymentType Type of payment (ETH or ERC20)
     * @param _tokenAddress Address of ERC20 token (if applicable)
     * @return agreementId The ID of the created agreement
     */
    function createAgreement(
        address _freelancer,
        string memory _title,
        string memory _description,
        uint256 _deadline,
        PaymentType _paymentType,
        address _tokenAddress
    ) external notPaused returns (uint256) {
        require(_freelancer != address(0), "Invalid freelancer address");
        require(_freelancer != msg.sender, "Client and freelancer cannot be the same");

        // If using ERC20, validate token
        if (_paymentType == PaymentType.ERC20) {
            require(_tokenAddress != address(0), "Invalid token address");
            require(approvedTokens[_tokenAddress], "Token not approved for use");
        }

        uint256 agreementId = nextAgreementId;
        nextAgreementId++;

        Agreement storage newAgreement = agreements[agreementId];
        newAgreement.id = agreementId;
        newAgreement.client = msg.sender;
        newAgreement.freelancer = _freelancer;
        newAgreement.title = _title;
        newAgreement.description = _description;
        newAgreement.createdAt = block.timestamp;
        newAgreement.deadline = _deadline;
        newAgreement.state = AgreementState.Created;
        newAgreement.paymentType = _paymentType;
        newAgreement.tokenAddress = _tokenAddress;

        // Track user agreements
        clientAgreements[msg.sender].push(agreementId);
        freelancerAgreements[_freelancer].push(agreementId);

        emit AgreementCreated(agreementId, msg.sender, _freelancer, 0, _paymentType);

        return agreementId;
    }

    /**
     * @dev Client funds the agreement
     * @param _agreementId ID of the agreement to fund
     */
    function fundAgreement(uint256 _agreementId)
        external
        payable
        onlyClient(_agreementId)
        agreementExists(_agreementId)
        notPaused
        nonReentrant
    {
        Agreement storage agreement = agreements[_agreementId];

        // Agreement must be in Created state to be funded
        require(agreement.state == AgreementState.Created, "Agreement is not in Created state");
        require(agreement.milestoneCount > 0, "Agreement must have at least one milestone");

        // Calculate platform fee
        uint256 platformFee = (agreement.totalAmount * platformFeeRate) / 10000;
        agreement.platformFee = platformFee;

        // Process based on payment type
        if (agreement.paymentType == PaymentType.ETH) {
            // Check if sufficient ETH is sent
            uint256 requiredAmount = agreement.totalAmount + platformFee;
            require(msg.value == requiredAmount, "Incorrect funding amount");
        } else {
            // Check if sufficient tokens are available and approved
            IERC20 token = IERC20(agreement.tokenAddress);
            uint256 requiredAmount = agreement.totalAmount + platformFee;

            require(token.allowance(msg.sender, address(this)) >= requiredAmount, "Insufficient token allowance");

            require(token.transferFrom(msg.sender, address(this), requiredAmount), "Token transfer failed");
        }

        // Update agreement state
        agreement.state = AgreementState.Funded;

        emit AgreementFunded(_agreementId, agreement.totalAmount + platformFee);
    }

    /**
     * @dev Cancel an agreement
     * @param _agreementId ID of the agreement
     */
    function cancelAgreement(uint256 _agreementId)
        external
        onlyParticipant(_agreementId)
        agreementExists(_agreementId)
        notPaused
        nonReentrant
    {
        Agreement storage agreement = agreements[_agreementId];

        // Only allow cancellation if no milestones are completed
        bool hasCompletedMilestones = false;
        for (uint256 i = 0; i < agreement.milestoneCount; i++) {
            if (agreement.milestones[i].state == MilestoneState.Completed) {
                hasCompletedMilestones = true;
                break;
            }
        }

        require(!hasCompletedMilestones, "Cannot cancel agreement with completed milestones");
        require(agreement.state != AgreementState.InDispute, "Cannot cancel agreement in dispute");

        // If client is cancelling, refund all remaining funds
        if (msg.sender == agreement.client) {
            uint256 remainingFunds = 0;

            // Calculate remaining funds
            for (uint256 i = 0; i < agreement.milestoneCount; i++) {
                if (agreement.milestones[i].state != MilestoneState.Completed) {
                    remainingFunds += agreement.milestones[i].amount;
                }
            }

            // Return platform fee as well if no milestones were completed
            if (!hasCompletedMilestones) {
                remainingFunds += agreement.platformFee;
            }

            // Update agreement state
            agreement.state = AgreementState.Cancelled;

            // Transfer funds back to client
            if (agreement.paymentType == PaymentType.ETH) {
                payable(agreement.client).transfer(remainingFunds);
            } else {
                IERC20 token = IERC20(agreement.tokenAddress);
                require(token.transfer(agreement.client, remainingFunds), "Token transfer failed");
            }
        }
        // If freelancer is cancelling
        else {
            // Freelancer can only cancel if no work has started
            bool workStarted = false;
            for (uint256 i = 0; i < agreement.milestoneCount; i++) {
                if (agreement.milestones[i].state != MilestoneState.NotStarted) {
                    workStarted = true;
                    break;
                }
            }

            require(!workStarted, "Cannot cancel after work has started");

            // Update agreement state
            agreement.state = AgreementState.Cancelled;

            // Return all funds to client
            uint256 totalFunds = agreement.totalAmount + agreement.platformFee;

            if (agreement.paymentType == PaymentType.ETH) {
                payable(agreement.client).transfer(totalFunds);
            } else {
                IERC20 token = IERC20(agreement.tokenAddress);
                require(token.transfer(agreement.client, totalFunds), "Token transfer failed");
            }
        }

        emit AgreementCancelled(_agreementId);
    }

    // ================ View Functions ================

    /**
     * @dev Get agreement details
     * @param _agreementId ID of the agreement
     * @return AgreementView struct
     */
    function getAgreement(uint256 _agreementId)
        external
        view
        agreementExists(_agreementId)
        returns (AgreementView memory)
    {
        Agreement storage agreement = agreements[_agreementId];

        return AgreementView({
            id: agreement.id,
            client: agreement.client,
            freelancer: agreement.freelancer,
            title: agreement.title,
            description: agreement.description,
            totalAmount: agreement.totalAmount,
            createdAt: agreement.createdAt,
            deadline: agreement.deadline,
            milestoneCount: agreement.milestoneCount,
            state: agreement.state,
            platformFee: agreement.platformFee,
            paymentType: agreement.paymentType,
            tokenAddress: agreement.tokenAddress,
            clientRating: agreement.clientRating,
            freelancerRating: agreement.freelancerRating
        });
    }

    /**
     * @dev Get milestone details
     * @param _agreementId ID of the agreement
     * @param _milestoneId ID of the milestone
     * @return MilestoneView struct
     */
    function getMilestone(uint256 _agreementId, uint256 _milestoneId)
        external
        view
        agreementExists(_agreementId)
        returns (MilestoneView memory)
    {
        Agreement storage agreement = agreements[_agreementId];
        require(_milestoneId < agreement.milestoneCount, "Milestone does not exist");

        Milestone storage milestone = agreement.milestones[_milestoneId];

        return MilestoneView({
            id: milestone.id,
            title: milestone.title,
            description: milestone.description,
            amount: milestone.amount,
            deadline: milestone.deadline,
            state: milestone.state,
            startedAt: milestone.startedAt,
            submittedAt: milestone.submittedAt,
            completedAt: milestone.completedAt,
            clientFeedback: milestone.clientFeedback,
            freelancerFeedback: milestone.freelancerFeedback,
            revisionCount: milestone.revisionCount,
            isDisputed: milestone.dispute.isDisputed
        });
    }

    /**
     * @dev Get all agreement IDs for a client
     * @param _client Address of the client
     * @return Array of agreement IDs
     */
    function getClientAgreements(address _client) external view returns (uint256[] memory) {
        return clientAgreements[_client];
    }

    /**
     * @dev Get all agreement IDs for a freelancer
     * @param _freelancer Address of the freelancer
     * @return Array of agreement IDs
     */
    function getFreelancerAgreements(address _freelancer) external view returns (uint256[] memory) {
        return freelancerAgreements[_freelancer];
    }

    /**
     * @dev Get user reputation score
     * @param _user Address of the user
     * @return Reputation score and completed jobs count
     */
    function getUserReputation(address _user) external view returns (uint256, uint256) {
        return (userReputationScore[_user], userCompletedJobs[_user]);
    }

    /**
     * @dev Emergency withdraw function (only owner)
     * @param _token Address of token to withdraw (address(0) for ETH)
     */
    function emergencyWithdraw(address _token) external onlyOwner {
        if (_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(_token);
            uint256 balance = token.balanceOf(address(this));
            require(token.transfer(owner(), balance), "Token transfer failed");
        }

        emit EmergencyAction("Emergency withdrawal", msg.sender);
    }

    // Function to receive ETH
    receive() external payable {}
}
