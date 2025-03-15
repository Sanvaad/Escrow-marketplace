// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DataStructures.sol";

/**
 * @title EscrowStorage
 * @dev Storage contract for the EscrowMarketplace ecosystem
 */
abstract contract EscrowStorage is Ownable, DataStructures {
    // ================ State Variables ================
    uint256 internal nextAgreementId = 1;
    mapping(uint256 agreementId => Agreement) internal agreements;

    // Platform fee percentage (in basis points: 100 = 1%)
    uint256 public platformFeeRate = 200; // 2% default fee
    address public platformWallet;

    // Emergency pause flag
    bool public paused = false;

    // User reputation tracking
    mapping(address => uint256) public userReputationScore;
    mapping(address => uint256) public userCompletedJobs;

    // Approved ERC20 tokens
    mapping(address => bool) public approvedTokens;

    // Dispute resolver addresses
    mapping(address => bool) public disputeResolvers;

    // User agreements tracking
    mapping(address => uint256[]) public clientAgreements;
    mapping(address => uint256[]) public freelancerAgreements;

    // ================ Events ================
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed client,
        address indexed freelancer,
        uint256 totalAmount,
        PaymentType paymentType
    );
    event AgreementFunded(uint256 indexed agreementId, uint256 amount);
    event MilestoneCreated(uint256 indexed agreementId, uint256 indexed milestoneId, uint256 amount);
    event MilestoneStarted(uint256 indexed agreementId, uint256 indexed milestoneId);
    event MilestoneSubmitted(uint256 indexed agreementId, uint256 indexed milestoneId);
    event MilestoneRevisionRequested(uint256 indexed agreementId, uint256 indexed milestoneId, string reason);
    event MilestoneApproved(uint256 indexed agreementId, uint256 indexed milestoneId);
    event MilestoneCompleted(uint256 indexed agreementId, uint256 indexed milestoneId, uint256 amount);
    event DisputeRaised(uint256 indexed agreementId, uint256 indexed milestoneId, address initiator);
    event DisputeResolved(
        uint256 indexed agreementId,
        uint256 indexed milestoneId,
        DisputeOutcome outcome,
        uint256 clientAmount,
        uint256 freelancerAmount
    );
    event AgreementCompleted(uint256 indexed agreementId);
    event AgreementCancelled(uint256 indexed agreementId);
    event UserRated(uint256 indexed agreementId, address indexed rated, uint256 rating);
    event EmergencyAction(string action, address indexed by);

    // ================ Constructor ================
    constructor() Ownable(msg.sender) {
        platformWallet = msg.sender;
    }

    // ================ Admin Functions ================

    /**
     * @dev Update platform fee rate
     * @param _newFeeRate New fee rate in basis points
     */
    function updatePlatformFeeRate(uint256 _newFeeRate) external onlyOwner {
        require(_newFeeRate <= 1000, "Fee rate cannot exceed 10%");
        platformFeeRate = _newFeeRate;
    }

    /**
     * @dev Update platform wallet address
     * @param _newWallet New platform wallet address
     */
    function updatePlatformWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "Invalid wallet address");
        platformWallet = _newWallet;
    }

    /**
     * @dev Add or remove an approved token
     * @param _tokenAddress Token contract address
     * @param _approved Whether the token is approved
     */
    function setApprovedToken(address _tokenAddress, bool _approved) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        approvedTokens[_tokenAddress] = _approved;
    }

    /**
     * @dev Add or remove a dispute resolver
     * @param _resolver Resolver address
     * @param _approved Whether the resolver is approved
     */
    function setDisputeResolver(address _resolver, bool _approved) external onlyOwner {
        require(_resolver != address(0), "Invalid resolver address");
        disputeResolvers[_resolver] = _approved;
    }

    /**
     * @dev Pause or unpause the contract
     * @param _paused New paused state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit EmergencyAction(_paused ? "Contract paused" : "Contract unpaused", msg.sender);
    }

    // ================ Modifiers ================
    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyDisputeResolver() {
        require(disputeResolvers[msg.sender], "Only dispute resolvers can perform this action");
        _;
    }

    modifier onlyClient(uint256 _agreementId) {
        require(agreements[_agreementId].client == msg.sender, "Only the client can perform this action");
        _;
    }

    modifier onlyFreelancer(uint256 _agreementId) {
        require(agreements[_agreementId].freelancer == msg.sender, "Only the freelancer can perform this action");
        _;
    }

    modifier onlyParticipant(uint256 _agreementId) {
        require(
            agreements[_agreementId].client == msg.sender || agreements[_agreementId].freelancer == msg.sender,
            "Only agreement participants can perform this action"
        );
        _;
    }

    modifier agreementExists(uint256 _agreementId) {
        require(_agreementId > 0 && _agreementId < nextAgreementId, "Agreement does not exist");
        _;
    }
}
