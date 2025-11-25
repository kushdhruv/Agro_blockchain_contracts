// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DisputeManager.sol";
import "../src/EscrowPayment.sol";
import "../src/Registration.sol";
import "../src/OracleManager.sol";
import "../src/ShipmentToken.sol";
import "./utils/KYCTestHelper.sol";

contract DisputeManagerTest is Test {
    Registration reg;
    EscrowPayment escrow;
    DisputeManager dm;
    KYCTestHelper kycHelper;
    ShipmentToken shipmentToken;

    function setUp() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        // Deploy OracleManager
        OracleManager om = new OracleManager(address(reg));
        // Deploy ShipmentToken
        shipmentToken = new ShipmentToken(address(reg), address(om), "Shipment", "SHP");
        // Deploy EscrowPayment
        escrow = new EscrowPayment(address(reg), address(shipmentToken));
        dm = new DisputeManager(address(reg), address(escrow), address(om));
        vm.stopPrank();
        kycHelper = new KYCTestHelper(reg, owner);
    }

    function testRaiseDispute() public {
        // Register and verify a farmer to raise dispute
        address farmer = makeAddr("farmer");
        
        // Register farmer using owner
        vm.prank(farmer);
        reg.registerParticipant(Registration.Role.FARMER, "farmerMeta");

        // Get KYC params and attest using the kycSigner from helper
        Registration.KYCAttestationParams memory params = kycHelper.createKYCParams(
            farmer,
            Registration.Role.FARMER,
            "farmerMeta",
            block.timestamp,
            0
        );

        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(params);
        
        vm.prank(farmer);
        uint256 id = dm.raiseDispute(keccak256("s1"), "evidence1");
        assertTrue(id > 0);
    }
}
