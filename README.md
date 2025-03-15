# Blockchain Escrow Marketplace

A secure, decentralized escrow platform for freelancers and clients, built on Ethereum.

## Overview

This smart contract system creates a trustless escrow service for freelance work, allowing clients and freelancers to collaborate safely without relying on traditional intermediaries. The platform supports milestone-based payments, dispute resolution, and reputation tracking.

## Features

- **Milestone-Based Payments:** Break projects into manageable chunks with separate deliverables and payments
- **Multiple Payment Options:** Support for ETH and any approved ERC20 tokens
- **Dispute Resolution:** Built-in arbitration system with configurable dispute resolvers
- **Reputation System:** Track performance ratings for both clients and freelancers
- **Flexible Payment Release:** Clients can approve work or request revisions
- **Secure Fund Management:** All funds held in escrow until work is approved
- **Platform Fee Management:** Configurable fee structure for platform sustainability

## Smart Contract Architecture

The system consists of several contracts with specialized functions:

- **DataStructures.sol:** Core data models and enums
- **EscrowStorage.sol:** State variables and storage management
- **MilestoneManager.sol:** Milestone creation and progression functionality
- **DisputeResolution.sol:** Dispute creation and resolution
- **EscrowMarketplace.sol:** Main contract that integrates all components

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (optional, for frontend integration)

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/blockchain-escrow-marketplace.git
cd blockchain-escrow-marketplace

# Install Foundry dependencies
forge install

# Set up environment
cp .env.example .env
# Edit .env with your credentials
```

## Development and Testing

```bash
# Run tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run a specific test
forge test --match-test testCompleteAgreementWithETH
```

## Deployment

### Local Development

```bash
# Start a local Ethereum node
anvil

# Deploy to local node
forge script script/DeployEscrowMarketplace.s.sol:DeployEscrowMarketplace --broadcast --rpc-url http://localhost:8545
```

### Testnet Deployment

Create a `.env` file with:
```
PRIVATE_KEY=your_private_key_without_0x_prefix
SEPOLIA_RPC_URL=your_sepolia_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key
```

Then deploy:
```bash
# Load environment variables
source .env

# Deploy to Sepolia testnet
forge script script/DeployEscrowMarketplace.s.sol:DeployEscrowMarketplace \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

## Usage Flow

1. **Create Agreement:** Client initiates a contract with a freelancer
2. **Add Milestones:** Client defines project deliverables and payments
3. **Fund Agreement:** Client deposits funds into escrow
4. **Start Work:** Freelancer begins working on milestones
5. **Submit for Review:** Freelancer submits completed work
6. **Approve or Request Revisions:** Client reviews and decides
7. **Payment Release:** Automatic payment upon approval
8. **Ratings:** Both parties rate each other after completion

## Security Considerations

- The contract uses OpenZeppelin's ReentrancyGuard to prevent re-entrancy attacks
- Administrative functions are protected by onlyOwner modifiers
- Platform fees are capped at 10% maximum
- Complete test coverage is maintained
- Emergency pause functionality available for critical situations

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
