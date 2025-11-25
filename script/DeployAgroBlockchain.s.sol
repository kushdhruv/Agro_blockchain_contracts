// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Registration.sol";
import "../src/OracleManager.sol";
import "../src/ShipmentToken.sol";
import "../src/EscrowPayment.sol";
import "../src/DisputeManager.sol";

contract DeployAgroBlockchain is Script {
    function run() external {
        // For local testing with Anvil, use default private key
        uint256 deployerKey = vm.envUint("PRIVATE_KEY"); // Set in .env or use default for Anvil

        vm.startBroadcast(deployerKey);

        // Deploy Registration
        Registration reg = new Registration();
        console.log("Registration:", address(reg));

        // Deploy OracleManager
        OracleManager om = new OracleManager(address(reg));
        console.log("OracleManager:", address(om));

        // Deploy ShipmentToken
        ShipmentToken st = new ShipmentToken(address(reg), address(om), "Shipment", "SHP");
        console.log("ShipmentToken:", address(st));

        // Deploy EscrowPayment (platform receiver is deployer for local, change for mainnet)
        EscrowPayment escrow = new EscrowPayment(msg.sender, address(st));
        console.log("EscrowPayment:", address(escrow));

        // Deploy DisputeManager
        DisputeManager dm = new DisputeManager(address(reg), address(escrow), address(om));
        console.log("DisputeManager:", address(dm));

        // Set managers for EscrowPayment
        escrow.setManager(address(st), true);
        escrow.setManager(address(dm), true);

        // Register deployer as admin (for local, change for mainnet)
       // reg.registerParticipant(msg.sender, Registration.Role.ADMIN, "deployerMeta");

        // Example: Add an oracle (replace with real oracle address for mainnet)
        // address oracle = 0x...;
        // reg.registerParticipant(oracle, Registration.Role.ORACLE(), "oracleMeta");
        // om.addOracle(oracle, "oracleMeta");

        vm.stopBroadcast();
    }
}

/*
To run locally with Anvil:
1. Start Anvil: anvil
2. Set PRIVATE_KEY in .env (or use Anvil's default key)
3. Run: forge script script/DeployAgroBlockchain.s.sol --broadcast --rpc-url http://127.0.0.1:8545

For mainnet/testnet:
- Change platform receiver in EscrowPayment to your platform address.
- Use real admin and oracle addresses.
- Set correct RPC URL and PRIVATE_KEY for your wallet.
*/
