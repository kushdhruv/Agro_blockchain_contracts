// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Registration.sol";
import "./utils/KYCTestHelper.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RegistrationTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using stdStorage for StdStorage;

    Registration reg;
    KYCTestHelper kycHelper;

    function setUp() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        vm.stopPrank();
        kycHelper = new KYCTestHelper(reg, owner);
    }

    function testInitialAdminIsKycVerified() view public {
        // Owner should be admin and KYC verified
        assertTrue(reg.isKycVerified(kycHelper.owner()));
        assertTrue(reg.hasRole(kycHelper.owner(), Registration.Role.ADMIN));
    }

    function testRegisterParticipant() public {
        address user = makeAddr("user1");
        vm.prank(user);
        reg.registerParticipant(Registration.Role.FARMER, "metaHash");
        assertFalse(reg.isKycVerified(user), "User should not be KYC verified immediately after registration");
        assertTrue(reg.hasRole(user, Registration.Role.FARMER));
        (Registration.Role role,, , , , bool active) = reg.getParticipant(user);
        assertEq(uint(role), uint(Registration.Role.FARMER));
        assertTrue(active);

        // After KYC attestation by KYC signer, the user should be verified
        Registration.KYCAttestationParams memory params = kycHelper.createKYCParams(
            user,
            Registration.Role.FARMER,
            "metaHash",
            block.timestamp,
            0
        );

        // Call kycAttestation with the kycSigner that signed the params
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(params);

        assertTrue(reg.isKycVerified(user), "User should be KYC verified after oracle attestation");
    }

    function testKYCAttestation() public {
        address participant = makeAddr("participant");
        
        // First register participant
        vm.prank(participant);
        reg.registerParticipant(Registration.Role.FARMER, "initialHash");
        
        // Setup KYC attestation
        Registration.KYCAttestationParams memory params = kycHelper.createKYCParams(
            participant,
            Registration.Role.FARMER,
            "newMetaHash",
            block.timestamp,
            0
        );

        // Execute KYC attestation using the kycSigner from the helper
        // (the one that actually signed the params)
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(params);

        // Verify KYC status
        assertTrue(reg.isKycVerified(participant));
        assertTrue(reg.hasRole(participant, Registration.Role.FARMER));
    }

    function testKYCAttestationInvalidSigner() public {
        address participant = makeAddr("participant");
        
        // Register participant
        vm.prank(participant);
        reg.registerParticipant(Registration.Role.FARMER, "initialHash");
        
        // Create params with signature from unregistered signer
        ( , uint256 wrongKey) = makeAddrAndKey("wrongSigner");
        bytes32 messageHash = keccak256(abi.encode(
            block.chainid,
            participant,
            Registration.Role.FARMER,
            keccak256(bytes("newMetaHash")),
            block.timestamp,
            0
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedMessageHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        Registration.KYCAttestationParams memory params = Registration.KYCAttestationParams({
            participant: participant,
            role: Registration.Role.FARMER,
            metaDataHash: "newMetaHash",
            timestamp: block.timestamp,
            nonce: 0,
            signature: wrongSignature
        });

        // Call with a registered KYC signer (kycHelper.kycSigner) but with a signature
        // from an unregistered signer. This should fail with "Invalid KYC signer"
        vm.prank(kycHelper.kycSigner());
        vm.expectRevert("Invalid KYC signer");
        reg.kycAttestation(params);
    }
}
