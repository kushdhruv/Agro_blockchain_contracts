# AgroChain - Complete Deployment Guide

## ✅ Successfully Deployed Contracts on Anvil

### Network Details
- **Network:** Anvil (Local Development)
- **Chain ID:** 31337
- **RPC URL:** http://127.0.0.1:8545
- **Deployer Account:** 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
- **Private Key Used:** 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

---

## 📋 Deployed Contract Addresses

| Contract Name | Address | Type |
|--------------|---------|------|
| **AgroToken** | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | ERC-20 Token |
| **Registration** | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | Identity & KYC |
| **OracleManager** | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` | Oracle Registry |
| **ShipmentToken** | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` | ERC-721 NFT |
| **EscrowPayment** | `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` | Payment Escrow |
| **DisputeManager** | `0x5FC8d32690cc91D4c39d9d3abcBD16989F875707` | Dispute Resolution |

---

## 🔧 How to Deploy

### Option 1: Using the Batch Script (Windows)
```bash
cd C:\AgroProject\Agro_blockchain_contracts
.\deploy-anvil.bat
```

### Option 2: Using the Shell Script (Git Bash/WSL)
```bash
cd C:\AgroProject\Agro_blockchain_contracts
chmod +x deploy-anvil.sh
./deploy-anvil.sh
```

### Option 3: Manual Deployment
```bash
# Step 1: Deploy AgroToken
forge script script/DeployAgroToken.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast

# Step 2: Deploy other contracts
forge script script/DeployAgroBlockchain.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

---

## 🎯 Frontend Integration

Update `C:\AgroProject\studio-AgroChainV2-main\studio-AgroChainV2-main\src\contracts\addresses.ts`:

```typescript
export const contractAddresses: ContractAddresses = {
  AgroToken: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  Registration: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  OracleManager: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  ShipmentToken: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  EscrowPayment: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  DisputeManager: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
} as const;
```

---

## 💰 Test Accounts with Pre-minted Tokens

The AgroToken deployment script automatically minted **100,000 AGT** to each of these Anvil test accounts:

| Account # | Address | Private Key | AGT Balance |
|-----------|---------|-------------|-------------|
| 0 | 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 | 100,000 AGT |
| 1 | 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d | 100,000 AGT |
| 2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a | 100,000 AGT |
| 3 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 | 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6 | 100,000 AGT |

---

## 📝 Next Steps

1. ✅ Contracts deployed successfully
2. 🔄 Update frontend `addresses.ts` with the addresses above
3. 🧪 Test the application with MetaMask connected to Anvil
4. 🎭 Use the test accounts to simulate different roles (Farmer, Transporter, Industry)

---

## 🚨 Important Notes

- **Anvil must be running** before deployment: `anvil`
- These addresses are **only valid for the current Anvil session**
- If you restart Anvil, you'll need to redeploy and update addresses
- For persistent testing, consider using a testnet like Sepolia or Mumbai
