// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; //
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {IRegistration} from "./interfaces/IRegistration.i.sol";
import {IOracleManager} from "./interfaces/IOracleManager.i.sol";

/**
* @title ShipmentToken (DigitalTwin)
* @notice Lightweight ERC721-based digital twin representing a physical shipment.
* - Uses your Registration contract for role/KYC checks via IRegistration.
* - Uses OracleManager to verify oracle-signed proofs and state transitions.
*
* Design choices for MVP:
* - tokenId = uint256(shipmentId) (where shipmentId is a bytes32 provided by caller). This
* allows external systems to reference shipmentId as bytes32 while ERC721 uses uint256.
* - Embeds a simple weighment history (array) per shipment for quick validations.
* - Anyone may submit oracle-signed payloads (relayers) — OracleManager verifies signer.
*/

import {IOracleManager} from "./interfaces/IOracleManager.i.sol";

contract ShipmentToken is ERC721, Ownable {
    // Modifier: onlyOracle
    modifier onlyOracle() {
        require(oracleManager.isOracle(msg.sender), "Not an authorized oracle");
        _;
    }
    using ECDSA for bytes32;

    IRegistration public registration;
    IOracleManager public oracleManager;

    uint8 public constant ROLE_FARMER = 1;
    uint8 public constant ROLE_TRANSPORTER = 2;
    uint8 public constant ROLE_INDUSTRY = 3;
    uint8 public constant ROLE_ADMIN = 5;
    uint8 public constant ROLE_ORACLE = 6;

    uint256 public constant MAX_TIMESTAMP_AGE = 10 minutes; // can be tuned based on requirements

    enum ShipmentState { OPEN, ASSIGNED, IN_TRANSIT, DELIVERED, VERIFIED, PAID, DISPUTED, CANCELLED }
    enum ProofType { GENERIC, PHOTO, WEIGHMENT, SCAN }

    struct Shipment{
        bytes32 shipmentId; //External shipment ID (e.g. UUIDv4)
        uint256 tokenId; //ERC721 token ID
        string metaDataHash; //IPFS hash reference to off-chain metadata
        ShipmentState state;
        address transporter; //assigned transporter
        address farmer; //origin farmer
        address industry; //destination industry
        string []proofHash; //IPFS hash reference to off-chain proof (e.g. delivery photo)
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Weighment {
        uint256 weighKg;
        string weighHash;
        address oracle;
        uint256 timestamp;
        uint256 nonce;
    }

    struct ProofInput {
        bytes32 shipmentId;
        ProofType proofType;
        string proofHash;
        uint256 timestamp;
        uint256 nonce;
        bytes signature;
    }

    struct WeighmentInput {
        bytes32 shipmentId;
        uint256 weighKg;
        string weighHash;
        uint256 timestamp;
        uint256 nonce;
        bytes signature;
    }

    struct StateInput {
        bytes32 shipmentId;
        ShipmentState newState;
        uint256 timestamp;
        uint256 nonce;
        bytes signature;
    }

    mapping(bytes32 => Shipment) private shipments; //shipmentId => Shipment
    mapping(uint256 => Weighment[]) private shipmentWeighments; //tokenId => Weighment[]
    // Track all shipmentIds for each address based on their role
    mapping(address => bytes32[]) private farmerShipments; // farmer => their shipmentIds
    mapping(address => bytes32[]) private transporterShipments; // transporter => their shipmentIds
    mapping(address => bytes32[]) private industryShipments; // industry => their shipmentIds
    // replay protection by signer nonce
    mapping(address => mapping(uint256 => bool)) public usedOracleNonces;

    error InvalidRegistrationAddress();
    error InvalidOracleManagerAddress();
    error NotKycVerified();
    error ShipmentDoesNotExist();
    error ShipmentAlreadyExists();
    error NotFarmer();
    error InvalidShipmentId();
    error IndustryAlreadySet();
    error NotIndustry();
    error NotOpenForAssignment();
    error NotAuthorizedToAssignTransporter();
    error NotTransporter();
    error IndustryNotSet();
    error InvalidTimestamp();
    error InvalidOracleSignature();
    error NonceUsed();
    error WeighmentMustBePositive();
    error ShipmentTokenDoesNotExist();
    error InvalidStateTransition();
    error TransporterNotAssigned();
    error NoWeighmentsRecorded();
    error InvalidNewState();

    event ShipmentCreated(bytes32 indexed shipmentId, uint256 indexed tokenId, address indexed farmer, string metaDataHash, uint256 timestamp);
    event IndustrySet(bytes32 indexed shipmentId , address indexed industry , uint256 timestamp);
    event TransporterAssigned(bytes32 indexed shipmentId, uint256 indexed tokenId, address indexed transporter, address assignedBy, uint256 timestamp);
    event ShipmentStateChanged(bytes32 indexed shipmentId, ShipmentState newState, uint256 timestamp);
    event ProofAttached(bytes32 indexed shipmentId, ProofType proofType, string proofHash, address indexed oracle, uint256 timestamp);

    constructor(address _registration, address _oracleManager , string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {
        if (_registration == address(0)) {
            revert InvalidRegistrationAddress();
        }
        if (_oracleManager == address(0)) {
            revert InvalidOracleManagerAddress();
        }
        registration = IRegistration(_registration);
        oracleManager = IOracleManager(_oracleManager);
    }

    modifier onlyKycVerified(address _addr) {
        if (!registration.isKycVerified(_addr)) {
            revert NotKycVerified();
        }
        _;
    }

    modifier shipmentExists(bytes32 _shipmentId) {
        if (shipments[_shipmentId].createdAt == 0) {
            revert ShipmentDoesNotExist();
        }
        _;
    }

    modifier shipmentNotExists(bytes32 _shipmentId) {
        if (shipments[_shipmentId].createdAt != 0) {
            revert ShipmentAlreadyExists();
        }
        _;
    }

    //Admin functions

    function setRegistrationContract(address _registration) external onlyOwner {
        if (_registration == address(0)) {
            revert InvalidRegistrationAddress();
        }
        registration = IRegistration(_registration);
    }
    function setOracleManager(address _oracleManager) external onlyOwner {
        if (_oracleManager == address(0)) {
            revert InvalidOracleManagerAddress();
        }
        oracleManager = IOracleManager(_oracleManager);
    }

    //core flows

    //Create a new shipment (mint token)
    function createShipment( bytes32 _shipmentId, string calldata _metaDataHash) external onlyKycVerified(msg.sender) shipmentNotExists(_shipmentId) {
        if (!registration.hasRole(msg.sender, ROLE_FARMER)) {
            revert NotFarmer();
        }
        uint256 tokenId = uint256(_shipmentId);
        _safeMint(msg.sender, tokenId);
        farmerShipments[msg.sender].push(_shipmentId);
        shipments[_shipmentId] = Shipment({
            shipmentId: _shipmentId,
            tokenId: tokenId,
            metaDataHash: _metaDataHash,
            state: ShipmentState.OPEN,
            transporter: address(0),
            farmer: msg.sender,
            industry: address(0),
            proofHash: new string[](0),
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        emit ShipmentCreated(_shipmentId, tokenId, msg.sender, _metaDataHash, block.timestamp);
    }

    // Set the destination industry for a shipment (must be called before assigning transporter)
    function setIndustry(bytes32 _shipmentId, address _industry) external onlyKycVerified(_industry) shipmentExists(_shipmentId) {
        if (_shipmentId == bytes32(0)) {
            revert InvalidShipmentId();
        }
        Shipment storage shipment = shipments[_shipmentId];
        if (shipment.industry != address(0)) {
            revert IndustryAlreadySet();
        }
        if (!registration.hasRole(_industry, ROLE_INDUSTRY)) {
            revert NotIndustry();
        }
        shipment.industry = _industry;
        industryShipments[_industry].push(_shipmentId);
        shipment.updatedAt = block.timestamp;
        emit IndustrySet(_shipmentId, _industry, block.timestamp);
    }

    //Assign a transporter to an open shipment can be done by the farmer or the industry or the admin
    function assignTransporter(bytes32 _shipmentId, address _transporter) external onlyKycVerified(msg.sender) onlyKycVerified(_transporter) shipmentExists(_shipmentId) {
        if (_shipmentId == bytes32(0)) {
            revert InvalidShipmentId();
        }
        Shipment storage shipment = shipments[_shipmentId];
        uint256 tokenId = shipment.tokenId;
        address owner = ownerOf(tokenId);
        if (shipment.state != ShipmentState.OPEN) {
            revert NotOpenForAssignment();
        }
        if (
            !(msg.sender == shipment.farmer ||
            msg.sender == shipment.industry ||
            registration.hasRole(msg.sender, ROLE_ADMIN) ||
            msg.sender == owner)
        ) {
            revert NotAuthorizedToAssignTransporter();
        }
        if (!registration.hasRole(_transporter, ROLE_TRANSPORTER)) {
            revert NotTransporter();
        }
        if (shipment.industry == address(0)) {
            revert IndustryNotSet();
        }
        shipment.transporter = _transporter;
        transporterShipments[_transporter].push(_shipmentId);
        shipment.state = ShipmentState.ASSIGNED;
        shipment.updatedAt = block.timestamp;
        emit TransporterAssigned(_shipmentId, tokenId, _transporter, msg.sender, block.timestamp);
        emit ShipmentStateChanged(_shipmentId,ShipmentState.ASSIGNED, block.timestamp);
    }

    function attachProof(ProofInput calldata input) external onlyOracle shipmentExists(input.shipmentId) {
        if (input.shipmentId == bytes32(0)) {
            revert InvalidShipmentId();
        }
        if (!(input.timestamp <= block.timestamp && block.timestamp - input.timestamp <= MAX_TIMESTAMP_AGE)) {
            revert InvalidTimestamp();
        }
        bytes32 payloadHash = keccak256(abi.encode(
            block.chainid,
            input.shipmentId,
            uint8(input.proofType),
            keccak256(bytes(input.proofHash)),
            input.timestamp,
            input.nonce
        ));
        (bool ok, address signer) = oracleManager.verifySignedHash(payloadHash, input.signature);
        if (!ok) {
            revert InvalidOracleSignature();
        }
        if (usedOracleNonces[signer][input.nonce]) {
            revert NonceUsed();
        }
        usedOracleNonces[signer][input.nonce] = true;
        Shipment storage shipment = shipments[input.shipmentId];
        shipment.proofHash.push(input.proofHash);
        shipment.updatedAt = block.timestamp;
        emit ProofAttached(input.shipmentId, input.proofType, input.proofHash, signer, block.timestamp);
    }

    function attachWeighment(WeighmentInput calldata input) external onlyOracle shipmentExists(input.shipmentId) {
        if (input.shipmentId == bytes32(0)) {
            revert InvalidShipmentId();
        }
        if (input.weighKg <= 0) {
            revert WeighmentMustBePositive();
        }
        if (!(input.timestamp <= block.timestamp && block.timestamp - input.timestamp <= MAX_TIMESTAMP_AGE)) {
            revert InvalidTimestamp();
        }
        bytes32 payloadHash = keccak256(abi.encode(
            block.chainid,
            input.shipmentId,
            input.weighKg,
            keccak256(bytes(input.weighHash)),
            input.timestamp,
            input.nonce
        ));
        (bool ok, address signer) = oracleManager.verifySignedHash(payloadHash, input.signature);
        if (!ok) {
            revert InvalidOracleSignature();
        }
        if (usedOracleNonces[signer][input.nonce]) {
            revert NonceUsed();
        }
        usedOracleNonces[signer][input.nonce] = true;
        uint256 tokenId = shipments[input.shipmentId].tokenId;
        if (ownerOf(tokenId) == address(0)) {
            revert ShipmentTokenDoesNotExist();
        }
        shipmentWeighments[tokenId].push(Weighment({
            weighKg: input.weighKg,
            weighHash: input.weighHash,
            oracle: signer,
            timestamp: input.timestamp,
            nonce: input.nonce
        }));
        shipments[input.shipmentId].proofHash.push(input.weighHash);
        shipments[input.shipmentId].updatedAt = block.timestamp;
        emit ProofAttached(input.shipmentId, ProofType.WEIGHMENT, input.weighHash, signer, block.timestamp);
    }

    function updateShipmentState(StateInput calldata input) external shipmentExists(input.shipmentId) {
        if (input.shipmentId == bytes32(0)) {
            revert InvalidShipmentId();
        }
        Shipment storage shipment = shipments[input.shipmentId];
        ShipmentState oldState = shipment.state;
        // Role-based state transitions
        if(input.newState == ShipmentState.ASSIGNED) {
            // Only Industry can assign
            if (oldState != ShipmentState.OPEN) revert InvalidStateTransition();
            if (msg.sender != shipment.industry) revert NotIndustry();
        } else if(input.newState == ShipmentState.IN_TRANSIT) {
            // Only Transporter can start transit
            if (oldState != ShipmentState.ASSIGNED) revert InvalidStateTransition();
            if (msg.sender != shipment.transporter) revert NotTransporter();
            if (shipment.transporter == address(0)) revert TransporterNotAssigned();
        } else if(input.newState == ShipmentState.DELIVERED) {
            // Only Transporter can mark delivered
            if (oldState != ShipmentState.IN_TRANSIT) revert InvalidStateTransition();
            if (msg.sender != shipment.transporter) revert NotTransporter();
        } else if(input.newState == ShipmentState.VERIFIED) {
            // Only Industry can verify
            if (oldState != ShipmentState.DELIVERED) revert InvalidStateTransition();
            if (msg.sender != shipment.industry) revert NotIndustry();
        } else if(input.newState == ShipmentState.PAID) {
            // Anyone can set PAID if previous state is VERIFIED
            if (oldState != ShipmentState.VERIFIED) revert InvalidStateTransition();
        } else if(input.newState == ShipmentState.DISPUTED) {
            // Anyone can dispute if delivered, verified, or paid
            if (!(oldState == ShipmentState.DELIVERED || oldState == ShipmentState.VERIFIED || oldState == ShipmentState.PAID)) revert InvalidStateTransition();
        } else if(input.newState == ShipmentState.CANCELLED) {
            // Only Farmer or Industry can cancel
            if (!(oldState == ShipmentState.OPEN || oldState == ShipmentState.ASSIGNED)) revert InvalidStateTransition();
            if (!(msg.sender == shipment.farmer || msg.sender == shipment.industry)) revert NotAuthorizedToAssignTransporter();
        } else {
            revert InvalidNewState();
        }
        shipments[input.shipmentId].state = input.newState;
        shipments[input.shipmentId].updatedAt = block.timestamp;
        emit ShipmentStateChanged(input.shipmentId, input.newState, block.timestamp);
    }

    //view functions

    function getFarmerShipments(address farmer) external view returns (bytes32[] memory) {
        return farmerShipments[farmer];
    }

    function getTransporterShipments(address transporter) external view returns (bytes32[] memory) {
        return transporterShipments[transporter];
    }

    function getIndustryShipments(address industry) external view returns (bytes32[] memory) {
        return industryShipments[industry];
    }

    function getShipment(bytes32 _shipmentId) external view shipmentExists(_shipmentId) returns (Shipment memory) {
        return shipments[_shipmentId];
    }

    function getWeighmentCount(bytes32 _shipmentId) external view shipmentExists(_shipmentId) returns (uint256) {
        uint256 tokenId = uint256(_shipmentId);
        return shipmentWeighments[tokenId].length;
    }

    function getWeighments(bytes32 _shipmentId) external view shipmentExists(_shipmentId) returns (Weighment[] memory) {
        uint256 tokenId = uint256(_shipmentId);
        return shipmentWeighments[tokenId];
    }

    function getLastWeighment(bytes32 _shipmentId) external view shipmentExists(_shipmentId) returns (Weighment memory) {
        uint256 tokenId = uint256(_shipmentId);
        uint256 count = shipmentWeighments[tokenId].length;
        if (count == 0) {
            revert NoWeighmentsRecorded();
        }
        return shipmentWeighments[tokenId][count - 1];
    }

    /// @notice Check if a shipment has been verified
    /// @param _shipmentId The ID of the shipment to check
    /// @return true if the shipment is in VERIFIED or PAID state
    function isShipmentVerified(bytes32 _shipmentId) external view shipmentExists(_shipmentId) returns (bool) {
        ShipmentState state = shipments[_shipmentId].state;
        return state == ShipmentState.VERIFIED || state == ShipmentState.PAID;
    }
   
}

