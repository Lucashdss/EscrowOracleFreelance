# EscrowFreelance Contract

## Overview
The **EscrowFreelance** smart contract is designed to facilitate secure and automated payments between clients and freelancers. It ensures that funds are held in escrow until the agreed-upon work is delivered and confirmed. The contract supports both **ETH** and **ERC20 tokens** for payments and integrates with **Chainlink Automation** to handle automated refunds and fund releases.

A **frontend** is currently in progress to provide an intuitive interface for interacting with the contract.

---

## Features
- **Escrow States**: Tracks the contract's state (`CREATED`, `FUNDED`, `DELIVERED`, `RELEASED`, `REFUNDED`).
- **Secure Payments**: Funds are held in escrow until delivery is confirmed.
- **Automated Upkeep**: Uses Chainlink Automation to:
  - Refund the client if the deadline passes without delivery.
  - Release funds to the freelancer upon delivery confirmation.
- **Flexible Payments**: Supports both ETH and ERC20 tokens.
- **Price Conversion**: Converts USD amounts to ETH using Chainlink Price Feeds.
- **Customizable Minimum Price**: Freelancers can set a minimum price for their services.

---

## How It Works
1. **Contract Deployment**:
   - The client deploys the contract, specifying the freelancer, delivery period, and payment token (ETH or ERC20).

2. **Funding**:
   - The client funds the contract with the agreed amount.

3. **Delivery**:
   - The freelancer marks the work as delivered.
   - The client confirms the delivery.

4. **Fund Release**:
   - Upon delivery confirmation, the funds are released to the freelancer.

5. **Refund**:
   - If the deadline passes without delivery, the funds are automatically refunded to the client.

---

## How to Use
### 1. Deployment
Deploy the contract by specifying:
- Freelancer's address.
- Delivery period (in seconds).
- Chainlink Price Feed address.
- Token address (use `address(0)` for ETH).

### 2. Funding
The client funds the contract using the `fund` function:
- For ETH: Send the amount in `msg.value`.
- For ERC20: Approve the contract to spend the token, then call `fund`.

### 3. Delivery and Confirmation
- The freelancer calls `markDelivered` to indicate the work is complete.
- The client calls `confirmDelivery` to confirm the work.

### 4. Automated Upkeep
- Chainlink Automation will monitor the contract and:
  - Refund the client if the deadline passes.
  - Release funds to the freelancer upon delivery confirmation.

---

## Frontend
A **frontend** is currently being developed to simplify interactions with the contract. It will allow users to:
- Fund the contract.
- Mark work as delivered.
- Confirm delivery.
- View the contract's state and details.