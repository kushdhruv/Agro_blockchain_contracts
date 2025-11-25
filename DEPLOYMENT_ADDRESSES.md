# AgroChain Contract Deployment Addresses

**Network:** Anvil (Chain ID: 31337)
**Deployed:** Latest run artifact
**Timestamp:** Run from `run-latest.json`

## Contract Addresses

| Contract | Address |
|----------|---------|
| Registration | `0x5fbdb2315678afecb367f032d93f642f64180aa3` |
| OracleManager | `0xe7f1725e7734ce288f8367e1bb143e90bb3f0512` |
| ShipmentToken (ERC721) | `0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0` |
| EscrowPayment | `0xcf7ed3acca5a467e9e704c703e8d87f634fb0fc9` |
| DisputeManager | `0xdc64a140aa3e981100a9beca4e685f962f0cf6c9` |

## Constructor Arguments

- **Registration**: No arguments
- **OracleManager**: `registration` = `0x5FbDB2315678afecb367f032d93F642f64180aa3`
- **ShipmentToken**: 
  - `registration` = `0x5FbDB2315678afecb367f032d93F642f64180aa3`
  - `oracleManager` = `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`
  - `name` = "Shipment"
  - `symbol` = "SHP"
- **EscrowPayment**:
  - `platformAddress` = `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (deployer)
  - `shipmentToken` = `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0`
- **DisputeManager**:
  - `registration` = `0x5FbDB2315678afecb367f032d93F642f64180aa3`
  - `escrow` = `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9`
  - `oracleManager` = `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`

## Deployment Order

1. Registration (no dependencies)
2. OracleManager (depends on Registration)
3. ShipmentToken (depends on Registration, OracleManager)
4. EscrowPayment (depends on ShipmentToken)
5. DisputeManager (depends on Registration, EscrowPayment, OracleManager)

## Frontend Integration

Update `src/contracts/addresses.ts` with these addresses:

```typescript
export const CONTRACT_ADDRESSES = {
  REGISTRATION: '0x5fbdb2315678afecb367f032d93f642f64180aa3',
  ORACLE_MANAGER: '0xe7f1725e7734ce288f8367e1bb143e90bb3f0512',
  SHIPMENT_TOKEN: '0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0',
  ESCROW_PAYMENT: '0xcf7ed3acca5a467e9e704c703e8d87f634fb0fc9',
  DISPUTE_MANAGER: '0xdc64a140aa3e981100a9beca4e685f962f0cf6c9',
} as const;
```
