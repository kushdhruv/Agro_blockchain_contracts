// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Registration.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract KYCTestHelper is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    Registration public reg;
    address public kycSigner;
    uint256 public kycSignerKey;
    address public owner;

    constructor(Registration _reg, address _owner) {
        reg = _reg;
        owner = _owner;
        // Create a signer for KYC attestations
        (kycSigner, kycSignerKey) = makeAddrAndKey("kycSigner");
        vm.prank(owner);
        reg.addKYCSigner(kycSigner);
    }

    function createKYCParams(
        address participant,
        Registration.Role role,
        string memory metaDataHash,
        uint256 timestamp,
        uint256 nonce
    ) public view returns (Registration.KYCAttestationParams memory) {
        bytes32 metaDataHashBytes = keccak256(bytes(metaDataHash));
        bytes32 messageHash = keccak256(abi.encode(
            block.chainid,
            participant,
            role,
            metaDataHashBytes,
            timestamp,
            nonce
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(kycSignerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return Registration.KYCAttestationParams({
            participant: participant,
            role: role,
            metaDataHash: metaDataHash,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature
        });
    }

    function setupParticipantWithKYC(
        address participant,
        Registration.Role role,
        string memory metaDataHash
    ) public returns (address oracle) {
        oracle = makeAddr("oracle");
        
        // Register oracle first
        reg.registerTrustedParticipant(oracle, Registration.Role.ORACLE, "oracleMetaHash");
        
        // Register participant
        vm.prank(participant);
        reg.registerParticipant(role, "initialHash");
        
        // Create and execute KYC attestation
        Registration.KYCAttestationParams memory params = createKYCParams(
            participant,
            role,
            metaDataHash,
            block.timestamp,
            0
        );

        vm.prank(oracle);
        reg.kycAttestation(params);
    }
}