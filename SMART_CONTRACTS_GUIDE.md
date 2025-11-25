# AgroChain Smart Contracts Guide

This document provides a detailed overview of the smart contracts used in the AgroChain project. These contracts collectively manage the supply chain lifecycle, from participant registration to shipment tracking and payment settlement.

## Core Contracts

### 1. Registration.sol
**Purpose:** Manages user identity, roles, and KYC (Know Your Customer) status.
**Key Features:**
- **Roles:** Supports multiple roles: `FARMER`, `TRANSPORTER`, `INDUSTRY`, `GOVT_AUTHORITY`, `ADMIN`, `ORACLE`.
- **KYC Process:** 
    - Users self-register with a role.
    - `kycStatus` starts as `PENDING`.
    - Authorized `kycSigners` can verify users via `kycAttestation`, upgrading status to `VERIFIED`.
- **Metadata:** Stores IPFS hashes for off-chain user data.

### 2. AgroToken.sol
**Purpose:** The native ERC-20 payment token for the ecosystem.
**Key Features:**
- **Symbol:** `AGT`
- **Supply:** Mints 1,000,000 tokens to the deployer upon initialization.
- **Functions:** Standard ERC-20 functions (`transfer`, `approve`, etc.) plus `mint` and `burn` capabilities for the owner.

### 3. ShipmentToken.sol (Digital Twin)
**Purpose:** An ERC-721 Non-Fungible Token (NFT) representing a physical shipment.
**Key Features:**
- **Digital Twin:** Each shipment is a unique NFT (`tokenId` derived from `shipmentId`).
- **State Machine:** Tracks shipment lifecycle: `OPEN` -> `ASSIGNED` -> `IN_TRANSIT` -> `DELIVERED` -> `VERIFIED` -> `PAID`.
- **Role-Based Actions:**
    - **Farmer:** Creates shipment (`createShipment`), assigns transporter.
    - **Industry:** Sets destination (`setIndustry`), verifies delivery.
    - **Transporter:** Updates status to `IN_TRANSIT`, `DELIVERED`.
- **Oracle Integration:** Allows registered oracles to attach off-chain proofs (photos, weighments) via `attachProof` and `attachWeighment`.

### 4. EscrowPayment.sol
**Purpose:** Securely manages funds during the shipment process.
**Key Features:**
- **Deposit:** Payer (Industry) deposits `AgroToken` or other ERC-20 tokens.
- **Splits:** Defines payment splits (in basis points) for Farmer, Transporter, and Platform.
- **Release:** Funds are released to parties only when the shipment is verified or by authorized managers.
- **Dispute Handling:** Can hold or refund payments if a dispute is raised.

### 5. DisputeManager.sol
**Purpose:** Handles conflict resolution between parties.
**Key Features:**
- **Dispute Lifecycle:** `OPEN` -> `RESOLVED` / `REJECTED`.
- **Evidence:** Allows parties to submit evidence (IPFS hashes).
- **Resolution:** Authorized resolvers can `REFUND_PAYER` or `RELEASE_FUNDS`, interacting directly with the `EscrowPayment` contract.

### 6. OracleManager.sol
**Purpose:** Manages the registry of authorized oracles.
**Key Features:**
- **Registry:** Adds, updates, and removes oracle addresses.
- **Verification:** Provides helper functions (`verifySignedPayload`, `verifySignedHash`) to verify signatures from authorized oracles, ensuring data integrity for off-chain inputs (like IoT data or manual verifications).

## Interaction Flow

1.  **Registration:** Users register and get KYC verified via `Registration.sol`.
2.  **Shipment Creation:** A Farmer mints a `ShipmentToken`.
3.  **Agreement:** Industry is set as the destination; Transporter is assigned.
4.  **Escrow:** Industry deposits funds into `EscrowPayment.sol`.
5.  **Transit:** Transporter updates status; Oracles may attach weighment/photo proofs to the `ShipmentToken`.
6.  **Completion:** Shipment is delivered and verified.
7.  **Payment:** Funds are released from Escrow to Farmer, Transporter, and Platform.
8.  **Dispute:** If issues arise, `DisputeManager` freezes funds until resolved.
