# Cross-chain Rebase Token

## Overview

1. A protocol that allows users to deposit into a vault and in return, receive rebase tokens that represent their underlying balance.
2. **Rebase Token Characteristics**:

   - `balanceOf` function is dynamic to show changing balances over time
   - Balance increases linearly with time
   - Mints tokens to users when they perform actions (minting, burning, transferring, or bridging)

3. **Interest Rate Mechanism**:
   - Individual interest rates set per user based on:
     - Global protocol interest rate at time of deposit
   - Global interest rate can only decrease (rewarding early adopters)

---

## Technology Stack

### Chainlink CCIP

Used for secure cross-chain communication and token transfers.

### Chainlink Local

Essential for local development and testing of CCIP applications:

#### Key Benefits:

1. **Simulates Real CCIP Infrastructure Locally**

   - Provides mock versions of critical CCIP components:
     - `Router` (handles cross-chain messaging)
     - `RMN` (Risk Management Network - security layer)
     - `LINK Token` (fee payments)
   - Eliminates need for live testnets during development

2. **Deterministic, Fast Testing**

   - Instant test execution (no real cross-chain delays)
   - Eliminates flaky tests from RPC issues or gas fluctuations

3. **Foundry Forking Integration**

   - Simulates multi-chain interactions (e.g., Ethereum + Arbitrum) in single tests
   - Usage pattern:
     ```solidity
     vm.createFork() + CCIPLocalSimulatorFork
     ```

4. **Cost & Efficiency Advantages**

   - Zero gas costs (vs. testnets)
   - No RPC rate limits

5. **Developer Experience**
   - Full Foundry stack traces for debugging
   - Seamless CI/CD pipeline integration


