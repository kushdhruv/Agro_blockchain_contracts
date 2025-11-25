# Agro Blockchain Contracts

This directory contains all smart contracts for the AgriChain supply chain platform, built with Solidity 0.8.20 and the Foundry framework.

## 📁 Directory Structure

```
Agro_blockchain_contracts/
├── src/                          # Source contracts
│   ├── Registration.sol          # Participant registry and KYC
│   ├── OracleManager.sol         # Oracle registry and signature verification
│   ├── ShipmentToken.sol         # ERC-721 shipment digital twins
│   ├── EscrowPayment.sol         # ERC-20 payment escrow
│   ├── DisputeManager.sol        # Dispute resolution system
│   └── interfaces/               # Contract interfaces
├── test/                         # Foundry tests
├── script/                        # Deployment scripts
├── out/                           # Compilation artifacts
├── cache/                         # Foundry cache
└── lib/                           # Dependencies (OpenZeppelin)
```

---

## 🏗️ Contract Architecture

### **Core Contracts**

#### **1. Registration.sol**
**Purpose**: Central participant registry with KYC management

**Key Features**:
- Role-based registration (Farmer, Transporter, Industry, Oracle, Admin, Govt)
- Self-registration for regular participants (starts as PENDING)
- Admin registration for trusted roles (auto-verified)
- Oracle-signed KYC attestations
- KYC status management (NONE, PENDING, VERIFIED, SUSPENDED, REVOKED)

**Access Control**:
- Owner can register trusted participants
- Owner manages KYC signers
- Anyone can self-register as farmer/transporter/industry

**Events**:
- `ParticipantRegistered(address, role, metadata, timestamp)`
- `KycStatusUpdated(address, oldStatus, newStatus, timestamp)`
- `ParticipantUpdated(address, oldMetadata, newMetadata, timestamp)`

---

#### **2. OracleManager.sol**
**Purpose**: Oracle registry and signature verification

**Key Features**:
- Oracle registration by admin/owner
- Active/inactive oracle management
- ECDSA signature verification
- Supports both raw payload and precomputed hash verification

**Functions**:
- `addOracle(address, metadata)` - Register oracle
- `isOracle(address)` - Check oracle authorization
- `verifySignedHash(hash, signature)` - Verify oracle signatures
- `verifySignedPayload(payload, signature)` - Verify raw payload signatures

**Verification Flow**:
1. Oracle signs payload/hash off-chain
2. Frontend submits payload/hash + signature
3. Contract recovers signer address
4. Contract verifies signer is authorized oracle

**Events**:
- `OracleAdded(address, metadata, timestamp)`
- `OracleUpdated(address, oldMetadata, newMetadata, timestamp)`
- `OracleRemoved(address, timestamp)`

---

#### **3. ShipmentToken.sol**
**Purpose**: ERC-721 digital twins for physical shipments

**Key Features**:
- Each shipment is an ERC-721 NFT
- State machine enforcing valid transitions
- Oracle-signed proofs and weighments
- Role-based shipment queries

**State Machine**:
```
OPEN (0)
  ↓
ASSIGNED (1)
  ↓
IN_TRANSIT (2)
  ↓
DELIVERED (3)
  ↓
VERIFIED (4)
  ↓
PAID (5)

Alternative paths:
- OPEN/ASSIGNED → CANCELLED (7)
- DELIVERED/VERIFIED/PAID → DISPUTED (6)
```

**Functions**:
- `createShipment(shipmentId, metadata)` - Farmer creates shipment
- `setIndustry(shipmentId, industry)` - Set destination
- `assignTransporter(shipmentId, transporter)` - Assign transporter
- `attachProof(input)` - Attach oracle-signed proof
- `attachWeighment(input)` - Attach verified weight data
- `updateShipmentState(input)` - Oracle-signed state transition

**Security**:
- Nonce-based replay protection
- Timestamp validation (10-minute window)
- Oracle signature verification
- State transition validation

**Events**:
- `ShipmentCreated(shipmentId, tokenId, farmer, metadata, timestamp)`
- `TransporterAssigned(shipmentId, transporter, assignedBy, timestamp)`
- `ShipmentStateChanged(shipmentId, newState, timestamp)`
- `ProofAttached(shipmentId, proofType, proofHash, oracle, timestamp)`

---

#### **4. EscrowPayment.sol**
**Purpose**: ERC-20 token escrow with automatic distribution

**Key Features**:
- Basis points (BPS) split configuration (must sum to 10000)
- Fee-on-transfer token support
- Cancellation window for payer protection
- Authorized manager system

**Escrow Lifecycle**:
```
NONE (0)
  ↓
DEPOSITED (1)
  ↓
HELD (2) → RELEASED (3) or REFUNDED (4)
```

**Functions**:
- `depositPayment(...)` - Industry deposits ERC-20 tokens
- `holdPayment(shipmentId)` - Authorized manager locks funds
- `releasePayment(shipmentId)` - Distribute funds per BPS splits
- `refundPayment(shipmentId)` - Refund to payer
- `cancelByPayer(shipmentId)` - Payer self-cancellation (within window)

**Distribution**:
- Funds split: `farmerBps%` + `transporterBps%` + `platformBps%` = 100%
- Platform receives remaining amount (handles rounding)

**Security**:
- ReentrancyGuard on all external calls
- SafeERC20 for token transfers
- Checks-effects-interactions pattern
- Stores actual received amount (supports fee-on-transfer tokens)

**Events**:
- `PaymentDeposited(...)`
- `PaymentHeld(shipmentId, timestamp)`
- `PaymentReleased(shipmentId, farmerAmount, transporterAmount, platformAmount, timestamp)`
- `PaymentRefunded(shipmentId, amount, timestamp)`
- `PaymentCancelled(shipmentId, payer, amount, timestamp)`

---

#### **5. DisputeManager.sol**
**Purpose**: Dispute lifecycle and resolution management

**Key Features**:
- Automatic escrow freezing on dispute
- Evidence collection with oracle signatures
- Authorized resolver system
- One open dispute per shipment

**Dispute Lifecycle**:
```
NONE (0)
  ↓
OPEN (1)
  ↓
RESOLVED (2) or REJECTED (3)
```

**Functions**:
- `raiseDispute(shipmentId, evidenceHash)` - Create dispute
- `addEvidence(disputeId, evidenceHash, oracleSignature, signedHash)` - Add evidence
- `resolveDispute(disputeId, resolution, note)` - Execute resolution

**Resolutions**:
- `REFUND_PAYER` - Refund escrow to payer
- `RELEASE_FUNDS` - Release escrow to beneficiaries

**Security**:
- KYC verification required to raise disputes
- Authorized resolvers only can resolve
- ReentrancyGuard on resolution execution
- Tracks open disputes per shipment (prevents duplicates)

**Events**:
- `DisputeRaised(disputeId, shipmentId, raisedBy, timestamp)`
- `EvidenceAdded(disputeId, evidenceHash, submittedBy, oracle, timestamp)`
- `DisputeResolved(disputeId, shipmentId, resolution, note, resolvedBy, timestamp)`

---

## 🔗 Contract Dependencies

```
Registration (no dependencies)
    ↓
OracleManager ──┐
    ↓            │
ShipmentToken ───┼──→ Registration
    ↓            │
EscrowPayment ───┘
    ↓
DisputeManager ───→ Registration, EscrowPayment, OracleManager
```

---

## 🧪 Testing

### **Run All Tests**
```bash
forge test
```

### **Run Specific Test**
```bash
forge test --match-path test/Registration.t.sol
```

### **Test Coverage**
```bash
forge coverage
```

### **Gas Reports**
```bash
forge test --gas-report
```

---

## 📦 Deployment

### **Local Development (Anvil)**

1. **Start Anvil**:
   ```bash
   anvil
   ```

2. **Deploy Contracts**:
   ```bash
   forge script script/DeployAgroBlockchain.s.sol \
     --broadcast \
     --rpc-url http://127.0.0.1:8545 \
     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```

3. **Copy Contract Addresses**:
   - Update `studio-AgroChainV2-main/studio-AgroChainV2-main/src/contracts/addresses.ts`
   - Update frontend ABIs if contract interfaces changed

### **Testnet/Mainnet Deployment**

1. **Set Environment Variables**:
   ```bash
   export PRIVATE_KEY=your_private_key
   export RPC_URL=your_rpc_url
   ```

2. **Deploy**:
   ```bash
   forge script script/DeployAgroBlockchain.s.sol \
     --broadcast \
     --rpc-url $RPC_URL \
     --private-key $PRIVATE_KEY
   ```

3. **Post-Deployment Setup**:
   - Register initial oracles
   - Set EscrowPayment authorized managers
   - Configure platform receiver address
   - Register admin accounts

---

## 🔐 Security Best Practices

1. **Ownership**:
   - Use multisig wallets for contract owners
   - Never use single-signature wallets in production

2. **Oracles**:
   - Distribute oracle keys securely
   - Implement oracle redundancy
   - Monitor for oracle misbehavior

3. **Authorized Managers**:
   - Use multisig or DAO governance
   - Regularly audit manager addresses
   - Implement time locks for critical operations

4. **Testing**:
   - Comprehensive test coverage
   - Fuzz testing for edge cases
   - Formal verification for critical paths

---

## 📝 Contract Interfaces

All contracts expose interfaces in `src/interfaces/`:

- `IRegistration.i.sol` - Registration contract interface
- `IOracleManager.i.sol` - OracleManager interface
- `IShipmentToken.i.sol` - ShipmentToken interface
- `IEscrowPayment.i.sol` - EscrowPayment interface

Use these interfaces for type-safe contract interactions.

---

## 🐛 Known Issues & Improvements

### **Current Issues** ✅ Fixed
- ~~DisputeManager: `openDisputeForShipment` mapping not set~~ ✅ Fixed
- ~~EscrowPayment: Fee-on-transfer token support~~ ✅ Fixed

### **Recommendations**
1. Add Pausable functionality for emergency stops
2. Implement time locks for critical admin functions
3. Add event emissions to `holdPayment()` for audit trail
4. Consider adding batch operations for efficiency
5. Add upgradeability patterns if needed

---

## 📚 Additional Resources

- **Foundry Book**: https://book.getfoundry.sh/
- **OpenZeppelin Contracts**: https://docs.openzeppelin.com/contracts
- **Solidity Docs**: https://docs.soliditylang.org/

---

## 🔄 Contract Upgrade Path

If contract upgrades are needed:

1. Deploy new contract versions
2. Update contract addresses in deployment script
3. Update frontend ABIs
4. Migrate state if necessary (for non-upgradeable contracts)

**Note**: Current contracts are NOT upgradeable. Consider using proxy patterns for upgradeability.

---

**Last Updated**: 2024  
**Solidity Version**: 0.8.20  
**License**: MIT
