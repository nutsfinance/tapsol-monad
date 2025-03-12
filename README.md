<div align="center">

# tapSOL

### Premium SOL liquidity on Monad

[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-e6e6e6?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://book.getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Wormhole](https://img.shields.io/badge/Powered%20by-Wormhole-8A2BE2)](https://wormhole.com/)
[![Monad](https://img.shields.io/badge/For-Monad-ff69b4)](https://monad.xyz/)

_Seamless cross-ecosystem yield without sacrifice_

</div>

## Project Overview

tapSOL is an asset DEX pool token with a self-pegging pricing mechanism designed to bootstrap the Monad ecosystem with blue-chip assets like SOL. As a high-performance L1, Monad would need access to established assets to jumpstart its DeFi ecosystem, and tapSOL solves this critical challenge by:

1. **Eliminating Liquidity Fragmentation**: Brings SOL liquidity to Monad seamlessly without siloing assets across chains
2. **Preserving Yield Generation**: Unlike conventional bridges where users lose staking rewards, tapSOL maintains full yield accrual from Solana
3. **Enabling Day-1 Utility**: Provides immediate collateral value and DeFi functionality on Monad
4. **Self-Pegging Mechanism**: Leverages Tapio's protocol to represent both capital value and yield of the underlying SOL assets

## Pitch deck

<div>
  <a href="https://docs.google.com/presentation/d/1EYOGs-Nu66wVLIdJsaNWJny2Y6h3c7wW2o1k6wmA3qs/edit?usp=sharing" target="_blank">
    <img width="1600" alt="View tapSOL Pitch Deck" src="https://github.com/user-attachments/assets/1e31f7a9-082a-4398-b59b-c94d2e7fb67c" />
  </a>
</div>

[Google Slides public link](https://docs.google.com/presentation/d/1EYOGs-Nu66wVLIdJsaNWJny2Y6h3c7wW2o1k6wmA3qs/edit?usp=sharing) — pitch deck provides an in-depth overview of tapSOL project, including:

- Explanation of the core problem we're solving
- Technical architecture and innovation highlights
- Growth strategy and next step details
- Team background and expertise

Reviewers are encouraged to explore the deck for a complete understanding of our project vision and [Demo section](#demo-and-deployment-status) below for a live demonstration of tapSOL.

## Technical Architecture

The tapSOL project leverages cutting-edge cross-chain infrastructure through a multi-layered architecture:

### 1. Solana SPA Layer `/solana/*`

Solana implementation features a Self-Pegging Asset (SPA) pool that:

- Combines native SOL and liquid staking derivatives (e.g., jitoSOL) into a correlated asset pool
- Issues tapSOL as a representation of pool share that maintains a peg to the underlying assets
- Implements a stable-swap AMM curve for efficient SOL-jitoSOL swaps with minimal slippage
- Maintains a verifiable on-chain exchange rate accessible via cross-chain queries
- Automatically accrues staking rewards from jitoSOL, improving tapSOL's value over time

### 2. Cross-Chain Oracle Layer

Cross-chain communication layer utilizes Wormhole NTT and Query to:

- Fetch the tapSOL-to-SOL exchange rate from the Solana pool state
- Verify the data through Wormhole's guardian network
- Propagate verified exchange rate data to the Monad chain
- Implement rate staleness checks with configurable thresholds for security

### 3. Monad Integration Layer

The Monad implementation includes:

- tapSOL exchange rate calculation mechanisms for accurate collateral valuation
- ERC20 token contract representing tapSOL with full yield accrual
- Integration with Pyth Network for real-time SOL price data
- Collateralization adapter for seamless integration with lending protocols

## Smart Contract Implementation

### Core Contracts

1. **TapSOLRate.sol**

   - Implements the Wormhole QueryResponse interface for cross-chain data verification
   - Parses and validates Solana account data for the tapSOL pool
   - Extracts and converts exchange rate information with appropriate scaling
   - Enforces data freshness through configurable staleness parameters
   - Provides a secure and reliable source of tapSOL/SOL exchange rates

2. **TapSOLToken.sol**
   - Extends Wormhole NTT standard for preserving economic rights
   - Implements controlled minting mechanisms for cross-chain bridged assets
   - Provides rate-aware functionality for SOL value calculations
   - Includes permissioned administrative controls for secure operation

### Supporting Contracts

3. **TapSOLCollateralAdapter.sol**

   - Calculates accurate USD value of tapSOL collateral based on:
     - Current tapSOL/SOL exchange rate (from TapSOLRate)
     - Current SOL/USD price (from PythSOLPriceOracle)
   - Applies configurable collateralization ratios for risk management
   - Exposes interfaces for integration with lending protocols

4. **PythSOLPriceOracle.sol**
   - Interfaces with the Pyth Network for secure, up-to-date SOL price data
   - Implements price staleness checks for additional security
   - Normalizes price data to standard 18-decimal format
   - Provides administrative controls for oracle configuration

## Key Technical Innovations

### Multi-Layered Yield Generation

One of tapSOL's most powerful features is its built-in yield generation from multiple sources:

1. **SOL Staking Rewards**: Captures staking yield from liquid staking derivatives in the pool
2. **Swap Fees**: Generates revenue from traders using the Tapio LP pools on Solana
3. **Redemption Fees**: Collects fees when users redeem assets from the pool
4. **DeFi Utility on Monad**: Enables additional yield opportunities through lending, liquidations, and other DeFi activities

This yield continues accruing even when tapSOL is being used on Monad, automatically updated via Wormhole Queries with no active management required from users.

### Other Key Innovations

1. **Self-Pegging Mechanism**: The pool serves as a robust pricing engine that maintains tapSOL's peg to underlying assets, reducing reliance on external oracles.

2. **Wormhole NTT Format**: Follows the Wormhole NTT token standard with secure burn/mint schema for cross-chain transfers.

3. **Trustless Verification**: Exchange rates are verified through Wormhole's guardian network, ensuring accurate and manipulation-resistant data transmission.

4. **Composable DeFi Building Block**: Serves as essential primitive for Monad's DeFi ecosystem, available from Day 1.

## Development and Deployment

This project is built with [Foundry](https://book.getfoundry.sh/), a blazing fast, portable and modular toolkit for Ethereum application development.

### Setup

```bash
# Clone the repository
git clone https://github.com/nutsfinance/tapsol-monad.git

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

```bash
# Run unit tests
forge test

# Run integration tests with fork
forge test --fork-url $MONAD_TESTNET_RPC
```

### Test Suite Architecture

> **⚠️ Note:** As of March 12, 2025, the test suite currently uses official mock Wormhole components provided by Wormhole. These mocks allow us to accurately test cross-chain functionality in a controlled environment while awaiting the complete deployment of Wormhole NTT/Queries on Monad.

The tapSOL test suite provides comprehensive coverage across all contract components with thorough unit and integration tests. The test architecture follows a modular approach with three main test files:

#### 1. TapSOLToken.t.sol

Core token functionality tests ensuring the ERC-20 representation on Monad operates correctly:

- Token minting/burning with proper access controls
- Burn rate calculation based on oracle data
- Exchange rate propagation and SOL value conversion
- Authorization controls for minter and owner functionality
- Edge cases including rate oracle not set scenarios

#### 2. TapSOLRate.t.sol

Cross-chain oracle tests that validate the Wormhole integration and rate mechanisms:

- Correct signature verification and message parsing
- Exchange rate calculation precision and mathematical invariants
- Wormhole guardian message validation
- Protection against timestamp underflows and other edge cases
- Rate staleness prevention mechanisms

#### 3. TapSOLIntegration.t.sol

End-to-end integration tests that simulate real-world usage scenarios:

- Complete user journey from minting to transfers to burning
- Collateral adapter functionality with different collateralization ratios
- Error handling for unauthorized access and invalid operations
- Monad-specific features like vote delegation
- EIP-2612 permit functionality

Each test file utilizes mock Wormhole components to simulate cross-chain messaging without external dependencies, ensuring deterministic and reliable test execution. The tests cover both happy path scenarios and error cases.

### Deployment

The deployment process involves several steps:

1. Deploy the rate oracle:

```bash
forge script script/DeployTapSOL.s.sol:DeployTapSOLRate --rpc-url $MONAD_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast
```

2. Deploy the token and supporting contracts:

```bash
forge script script/DeployTapSOL.s.sol:DeployTapSOLToken --rpc-url $MONAD_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast
```

## Security Considerations

- Rate staleness checks to prevent outdated exchange rates
- Permissioned admin controls with proper access controls
- Oracle failsafe mechanisms for price feed protection
- NTT implementation to prevent token transfers and maintain cross-chain integrity

## Future Vision

While tapSOL is our first implementation, our vision extends much further:

1. **Expanded Asset Coverage**: Develop tapMON and tapSUI to bring the same self-pegging yield mechanics to other premium blockchain assets

2. **Unified Liquidity Layer**: Create a cross-chain liquidity system where Monad becomes the central hub for yield-bearing assets from multiple blockchains

3. **Advanced DeFi Primitives**:

   - Leveraged staking positions
   - Cross-chain yield optimizer protocols
   - SOL-based derivatives markets on Monad

4. **Full Integration Ecosystem**:
   - Native integration with Monad's lending protocols
   - Liquidity provision for DEXs
   - Yield aggregation strategies

This can position Monad as the premier cross-chain financial hub with unmatched perf/efficiency and yield optimization capabilities.

## Demo and Deployment Status

> **Important Note for Monad Hackathon**

As of March 12, 2025, a complete live demo of tapSOL on Monad Testnet is not possible due to the current state of infrastructure. The NTT and Queries services required for cross-chain communication between Solana Devnet and Monad Testnet are still in the deployment phase &mdash; although they were available on Monad Devnet, which was deprecated last week.

To demonstrate the functionality of tapSOL:

1. **Test Suite**: We have implemented comprehensive tests using official Wormhole mock components.

   ```bash
   # Run integration tests with fork
   forge test --fork-url $MONAD_TESTNET_RPC
   ```

2. **Screencast Demo**: Screencast showing the local operation of tapSOL, demonstrating:

   - Cross-chain SOL value representation
   - Exchange rate querying via Wormhole mocks
   - Complete user flow for minting tokens

## License

This project is licensed under the MIT License.
