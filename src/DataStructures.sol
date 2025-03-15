// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DataStructures
 * @dev Data structures shared across the EscrowMarketplace contracts
 */
contract DataStructures {
    // Escrow agreement states
    enum AgreementState {
        Created,
        Funded,
        InProgress,
        InDispute,
        Completed,
        Cancelled
    }

    // Milestone states
    enum MilestoneState {
        NotStarted,
        InProgress,
        ReviewRequested,
        Approved,
        Disputed,
        Completed,
        Cancelled
    }

    // Payment types supported
    enum PaymentType {
        ETH,
        ERC20
    }

    enum DisputeOutcome {
        None,
        ClientWins,
        FreelancerWins,
        Compromise
    }

    // Main Agreement struct
    struct Agreement {
        uint256 id;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 totalAmount;
        uint256 createdAt;
        uint256 milestoneCount;
        uint256 deadline;
        AgreementState state;
        uint256 platformFee;
        PaymentType paymentType;
        address tokenAddress;
        uint256 clientRating;
        uint256 freelancerRating;
        mapping(uint256 milestoneId => Milestone) milestones;
    }

    // Milestone struct
    struct Milestone {
        uint256 id;
        string title;
        string description;
        uint256 amount;
        uint256 deadline;
        MilestoneState state;
        uint256 startedAt;
        uint256 submittedAt;
        uint256 completedAt;
        string clientFeedback;
        string freelancerFeedback;
        uint256 revisionCount;
        DisputeDetail dispute;
    }

    // Dispute details
    struct DisputeDetail {
        bool isDisputed;
        string clientReason;
        string freelancerResponse;
        string resolverNotes;
        DisputeOutcome outcome;
        uint256 createdAt;
        uint256 resolvedAt;
        uint256 clientAmount;
        uint256 freelancerAmount;
    }

    // Public readable structures for frontend
    struct MilestoneView {
        uint256 id;
        string title;
        string description;
        uint256 amount;
        uint256 deadline;
        MilestoneState state;
        uint256 startedAt;
        uint256 submittedAt;
        uint256 completedAt;
        string clientFeedback;
        string freelancerFeedback;
        uint256 revisionCount;
        bool isDisputed;
    }

    struct AgreementView {
        uint256 id;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 totalAmount;
        uint256 createdAt;
        uint256 deadline;
        uint256 milestoneCount;
        AgreementState state;
        uint256 platformFee;
        PaymentType paymentType;
        address tokenAddress;
        uint256 clientRating;
        uint256 freelancerRating;
    }
}
