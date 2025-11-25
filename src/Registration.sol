//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; //Using ECDSA signature verification for KYC attestations.
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


contract Registration is Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    uint256 public constant MAX_TIMESTAMP_AGE = 10 minutes; // can be tuned based on requirements

    enum Role { UNREGISTERED , FARMER , TRANSPORTER , INDUSTRY , GOVT_AUTHORITY , ADMIN , ORACLE}
    enum KYCStatus {NONE, PENDING, VERIFIED, SUSPENDED, REVOKED}

    struct Participant {
        Role role;
        KYCStatus kycStatus;
        uint256 createdAt;
        uint256 updatedAt;
        bool active;
        string metaDataHash; //IPFS hash reference to off-chain metadata
    }

    struct KYCAttestationParams {
        address participant;
        Role role;
        string metaDataHash;
        uint256 timestamp;
        uint256 nonce;
        bytes signature;
    }

    mapping(address => Participant) private participants;
    mapping(address => bool) public kycSigners; //Addresses authorized to sign KYC attestations

    event ParticipantRegistered(address indexed participant, Role role,string metaDataHash, uint256 timestamp);
    event KycSignerAdded(address indexed signer);
    event KycSignerRemoved(address indexed signer);
    event KycStatusUpdated(address indexed participant, KYCStatus oldStatus, KYCStatus newStatus, uint256 timestamp);
    event ParticipantUpdated(address indexed participant, string oldMetaDataHash, string newMetaDataHash, uint256 timestamp);

    modifier onlyActiveParticipant(address _addr) {
        require(participants[_addr].active, "Not an active participant");
        _;
    }
    modifier onlyRole(address _addr,Role _role) {
        require(participants[_addr].role == _role, "Address doesn't have required role");
        _;
    }
    modifier onlyAuthorized() {
        require(msg.sender == owner() || participants[msg.sender].role == Role.ADMIN || participants[msg.sender].role == Role.GOVT_AUTHORITY, "Not authorized");
        _;
    }
    constructor() Ownable(msg.sender) {
        //the deployer is the initial admin
        participants[msg.sender] = Participant({
            role: Role.ADMIN,
            kycStatus: KYCStatus.VERIFIED,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true,
            metaDataHash: ""
        });

        emit ParticipantRegistered(msg.sender, Role.ADMIN," " , block.timestamp);
    }

    //admin functions

    function addKYCSigner(address _signer) public onlyAuthorized {
        require(_signer != address(0), "Invalid signer address");
        kycSigners[_signer] = true;
        emit KycSignerAdded(_signer);
    }

    function removeKYCSigner(address _signer) public onlyAuthorized {
        require(kycSigners[_signer], "Signer not found");
        kycSigners[_signer] = false;
        emit KycSignerRemoved(_signer);
    }

    //Register trusted roles like oracles and admins (owner only, auto-verified)
    function registerTrustedParticipant(
        address _addr,
        Role _role,
        string calldata _metaDataHash
    ) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        require(participants[_addr].active == false, "Participant already registered");
        require(_role == Role.ORACLE || _role == Role.ADMIN || _role == Role.GOVT_AUTHORITY, "Role not allowed for direct verification");

        participants[_addr] = Participant({
            role: _role,
            kycStatus: KYCStatus.VERIFIED,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true,
            metaDataHash: _metaDataHash
        });

        if(_role != Role.ORACLE)
        {
            addKYCSigner(_addr); //Trusted participants can also be KYC signers
        }
        emit ParticipantRegistered(_addr, _role, _metaDataHash, block.timestamp);
    }

    //Self registration for normal participants (farmers, transporters, industry)
    function registerParticipant(
        Role _role,
        string calldata _metaDataHash
    ) external {
        require(msg.sender != address(0), "Invalid address");
        require(participants[msg.sender].active == false, "Participant already registered");
        require(_role == Role.FARMER || _role == Role.TRANSPORTER || _role == Role.INDUSTRY, "Invalid role for self-registration");

        participants[msg.sender] = Participant({
            role: _role,
            kycStatus: KYCStatus.PENDING, // Start with pending KYC
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true,
            metaDataHash: _metaDataHash
        });
        emit ParticipantRegistered(msg.sender, _role, _metaDataHash, block.timestamp);
    }

    //kyc attestation flow
    //Attestation message format (off-chain) to be signed by registered KYC signer:
    function kycAttestation(KYCAttestationParams calldata params) external {
        require(kycSigners[msg.sender], "Only KYC signers can attest");
        require(participants[params.participant].active, "Participant not registered");
        require(params.role != Role.UNREGISTERED, "Invalid role");
        require(block.timestamp - params.timestamp <= MAX_TIMESTAMP_AGE, "Attestation expired"); //Attestation validity check

        bytes32 metaDataHashBytes = keccak256(bytes(params.metaDataHash));
        bytes32 messageHash = keccak256(abi.encode(
            block.chainid,
            params.participant,
            params.role,
            metaDataHashBytes,
            params.timestamp,
            params.nonce
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(params.signature);
        require(kycSigners[signer], "Invalid KYC signer");
        //Update participant details
        KYCStatus old = participants[params.participant].kycStatus;

        participants[params.participant].role = params.role;
        participants[params.participant].kycStatus = KYCStatus.VERIFIED;
        participants[params.participant].updatedAt = block.timestamp;
        participants[params.participant].metaDataHash = params.metaDataHash;
        participants[params.participant].active = true;
        emit ParticipantRegistered(params.participant, params.role, params.metaDataHash, block.timestamp);
        emit KycStatusUpdated(params.participant, old, KYCStatus.VERIFIED, block.timestamp);
    }

    //Participant updating their metadata
    function updateMetaData(string calldata _metaDataHash ,bool isCritical) external onlyActiveParticipant(msg.sender){
        Participant storage participant = participants[msg.sender];
        require(participant.role != Role.UNREGISTERED, "Participant not active");
        KYCStatus old = participant.kycStatus;
        string memory oldMetaDataHash = participant.metaDataHash;
        participant.metaDataHash = _metaDataHash;
        participant.updatedAt = block.timestamp;

        if(isCritical) {
            participant.kycStatus = KYCStatus.PENDING; //Trigger re-KYC if critical data changes
            emit KycStatusUpdated(msg.sender, old, KYCStatus.PENDING, block.timestamp);
        }
        emit ParticipantUpdated(msg.sender, oldMetaDataHash, _metaDataHash, block.timestamp);
    }
        
    // admin functions to suspend/revoke KYC
    function setKycStatus (address _participant, KYCStatus _status) external onlyAuthorized onlyActiveParticipant(_participant) {
        Participant storage participant = participants[_participant];
        require(participant.role != Role.UNREGISTERED, "Participant not active");
        KYCStatus old = participant.kycStatus;
        participant.kycStatus = _status;
        participant.updatedAt = block.timestamp;
        emit KycStatusUpdated(_participant, old, _status, block.timestamp);
    }

    function revokeParticipant(address _participant) external onlyAuthorized onlyActiveParticipant(_participant) {
        Participant storage participant = participants[_participant];
        require(participant.role != Role.UNREGISTERED, "Participant not active");
        KYCStatus old = participant.kycStatus;
        participant.kycStatus = KYCStatus.REVOKED;
        participant.active = false;
        participant.updatedAt = block.timestamp;

        if(kycSigners[_participant]) {
            removeKYCSigner(_participant); //Remove from KYC signers if applicable
        }
        emit KycStatusUpdated(_participant, old, KYCStatus.REVOKED, block.timestamp);
    }

    //view functions
    function getParticipant(address _addr) external view returns (
        Role role,
        KYCStatus kyc,
        uint256 createdAt,
        uint256 updatedAt,
        bool active) {
        Participant memory p = participants[_addr];
        return (p.role, p.kycStatus, p.createdAt, p.updatedAt, p.active);
    }

    function getParticipantFull(address _addr) external view onlyAuthorized returns (
        Role role,
        KYCStatus kyc,
        string memory metadataHash,
        uint256 createdAt,
        uint256 updatedAt,
        bool active) {
        Participant memory p = participants[_addr];
        return (p.role, p.kycStatus, p.metaDataHash, p.createdAt, p.updatedAt, p.active);
    }

    function hasRole(address _addr, Role _role) external view returns (bool) {
        return participants[_addr].role == _role && participants[_addr].active;
    }

    function isKycVerified(address _addr) external view returns (bool) {
        return participants[_addr].kycStatus == KYCStatus.VERIFIED && participants[_addr].active;
    }

    function kycStatus(address _addr) external view returns (KYCStatus) {
        return participants[_addr].kycStatus;
    }

}

