// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ShipmentToken.sol";
import "../src/Registration.sol";
import "./utils/KYCTestHelper.sol";

contract MockOracleManager {
    function verifySignedPayload(bytes calldata, bytes calldata) external pure returns (bool, address) {
        return (true, address(0xBEEF));
    }
    function verifySignedHash(bytes32, bytes calldata) external pure returns (bool, address) {
        return (true, address(0xBEEF));
    }
    function isOracle(address) external pure returns (bool) { return true; }
}

contract ShipmentTokenTest is Test {
    Registration reg;
    MockOracleManager mockOm;
    ShipmentToken st;
    KYCTestHelper kycHelper;

    function setUp() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        mockOm = new MockOracleManager();
        st = new ShipmentToken(address(reg), address(mockOm), "Ship", "SHP");
        vm.stopPrank();
        kycHelper = new KYCTestHelper(reg, owner);
    }

    function testCreateShipment() public {
        // create a separate farmer account and register it with KYC
        address farmer = makeAddr("farmer");
        
        // Register farmer
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

        bytes32 shipmentId = keccak256("s1");
        vm.prank(farmer);
        st.createShipment(shipmentId, "metaHash");
        (ShipmentToken.Shipment memory s) = st.getShipment(shipmentId);
        assertEq(s.tokenId, uint256(shipmentId));
        assertEq(s.farmer, farmer);
    }
}
