//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEscrowPayment} from "./interfaces/IEscrowPayment.i.sol";
import {IRegistration} from "./interfaces/IRegistration.i.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IOracleManager} from "./interfaces/IOracleManager.i.sol";

contract DisputeManager is Ownable , ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    
    IRegistration public registrationContract;

    IEscrowPayment public escrowContract;
    IOracleManager public oracleManager;
    // Modifier: onlyOracle
    modifier onlyOracle() {
        require(oracleManager.isOracle(msg.sender), "Not an authorized oracle");
        _;
    }

    enum DisputeStatus {NONE,OPEN,RESOLVED,REJECTED}
    enum Resolution {NONE,REFUND_PAYER,RELEASE_FUNDS}

    struct Evidence {
        string evidenceHash; //IPFS CID or pointer
        address submittedBy; //who submitted evidence
        uint256 timestamp;
        address oracle; //which oracle submitted evidence
    }
    
    struct Dispute {
        uint256 disputeId;
        bytes32 shipmentId;
        address raisedBy; //who raised the dispute (payer/farmer/transporter)
        DisputeStatus status;
        Resolution resolution;
        string resolutionNote; //optional note on resoltion
        address resolvedBy;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    uint256 private _nextDisputeId = 1;
    mapping(uint256 => Dispute) public disputes; //disputeId -> Dispute
    mapping(uint256 => Evidence[]) public disputeEvidences; //disputeId -> Evidence[]
    mapping(address => bool) public authorizedResolver; 
    mapping(bytes32 => uint256) public openDisputeForShipment; // shipmentId => disputeId (0 = none)


    event RegistrationContractUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);
    event EscrowContractUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);
    event ResolverUpdated(address indexed resolver, bool authorized, uint256 timestamp);
    event DisputeRaised(uint256 indexed disputeId, bytes32 indexed shipmentId, address indexed raisedBy, uint256 timestamp);
    event EvidenceAdded(uint256 indexed disputeId, string evidenceHash, address indexed submittedBy, address indexed oracle, uint256 timestamp);
    event DisputeResolved(uint256 indexed disputeId, bytes32 indexed shipmentId, Resolution resolution, string resolutionNote, address indexed resolvedBy, uint256 timestamp);

    constructor(address _registrationContract,address _escrowContract, address _oracleManager) Ownable(msg.sender) {
        require(_registrationContract != address(0), "Invalid registration contract");
        require(_escrowContract != address(0), "Invalid escrow contract");
        require(_oracleManager != address(0), "Invalid oracle manager");
        registrationContract = IRegistration(_registrationContract);
        escrowContract = IEscrowPayment(_escrowContract);
        oracleManager = IOracleManager(_oracleManager);
    }

    modifier onlyKyc(){
        require(registrationContract.isKycVerified(msg.sender), "KYC required");
        _;
    }
    modifier onlyResolver(){
        require(authorizedResolver[msg.sender], "Not an authorized oracle");
        _;
    }

    //admin functions
    function setRegistrationContract(address _registrationContract) external onlyOwner {
        require(_registrationContract != address(0), "Invalid registration contract");
        address old = address(registrationContract);
        registrationContract = IRegistration(_registrationContract);

        emit RegistrationContractUpdated(old,_registrationContract,block.timestamp);
    }

    function setEscrowContract(address _escrow) external onlyOwner {
        require(_escrow != address(0), "Invalid escrow contract");
        address old = address(escrowContract);

        escrowContract = IEscrowPayment(_escrow);
        emit EscrowContractUpdated(old,_escrow,block.timestamp);
    }

    function setResolver(address _resolver,bool _authorized) external onlyOwner {
        require(_resolver != address(0), "Invalid resolver address");
        authorizedResolver[_resolver] = _authorized;

        emit ResolverUpdated(_resolver,_authorized,block.timestamp);
    }

    //function will attempt to call EscrowPayment.holdPayment to freeze funds.
    function raiseDispute(bytes32 _shipmentId , string calldata _evidenceHash) external onlyKyc returns (uint256){
        require(_shipmentId != bytes32(0), "Invalid shipmentId");
        require(openDisputeForShipment[_shipmentId] == 0, "Open dispute exists for shipment");
        
        uint256 disputeId = _nextDisputeId++;
        disputes[disputeId] = Dispute({
            disputeId: disputeId,
            shipmentId: _shipmentId,
            raisedBy: msg.sender,
            status: DisputeStatus.OPEN,
            resolution:Resolution.NONE,
            resolutionNote:"",
            resolvedBy:address(0),
            createdAt:block.timestamp,
            resolvedAt:0
        });

        //store initial evidence
        disputeEvidences[disputeId].push(Evidence({
            evidenceHash:_evidenceHash,
            submittedBy:msg.sender,
            timestamp:block.timestamp,
            oracle:address(0)
        }));

        //attempt to hold payment in escrow
        try escrowContract.holdPayment(_shipmentId) {
            // success
        } catch{
            // failure - we still create dispute but no revert back
        }
        
        // Mark this shipment as having an open dispute
        openDisputeForShipment[_shipmentId] = disputeId;
        
        emit DisputeRaised(disputeId,_shipmentId,msg.sender,block.timestamp);
        return disputeId;
    }

    //add evidence to existing dispute
    function addEvidence(uint256 _disputeId, string calldata _evidenceHash, bytes calldata _oracleSignature, bytes32 _oracleSignedHash) external onlyKyc returns(bool){
        require(disputes[_disputeId].status == DisputeStatus.OPEN, "Dispute not open");
        require(bytes(_evidenceHash).length > 0, "Invalid evidence hash");

        address oracleAddr = address(0);
        if(_oracleSignature.length > 0 && _oracleSignedHash != bytes32(0)){
            //verify oracle signature
            bytes32 messageHash = _oracleSignedHash.toEthSignedMessageHash();
            oracleAddr = messageHash.recover(_oracleSignature);
            require(oracleManager.isOracle(oracleAddr), "Oracle signature not from authorized oracle");
        }

        disputeEvidences[_disputeId].push(Evidence({
            evidenceHash: _evidenceHash,
            submittedBy: msg.sender,
            timestamp: block.timestamp,
            oracle: oracleAddr
        }));
        
        emit  EvidenceAdded(_disputeId, _evidenceHash, msg.sender, oracleAddr, block.timestamp);
        return true;
    }

    // only authorized resolver or owner can resolve dispute
    function resolveDispute(uint256 _disputeId,Resolution _resolution, string calldata _resolutionNote) external nonReentrant onlyResolver returns(bool){
        require(disputes[_disputeId].status == DisputeStatus.OPEN, "Dispute not open");
        require(_disputeId > 0 && _disputeId < _nextDisputeId, "Invalid disputeId");
        
        Dispute storage d = disputes[_disputeId];

        //execute resoltion
        if(_resolution == Resolution.REFUND_PAYER){
           try escrowContract.refundPayment(d.shipmentId)
           {
             //success
           } catch{
               revert("Refund failed");
           }
        }
        else if(_resolution == Resolution.RELEASE_FUNDS){
           try escrowContract.releasePayment(d.shipmentId)
           {
             //success
           } catch{
                revert("Release funds failed");
           }
        }
        else{
            revert("Invalid resolution");
        }

        d.status = DisputeStatus.RESOLVED;
        d.resolution= _resolution;
        d.resolutionNote = _resolutionNote;
        d.resolvedBy = msg.sender;
        d.resolvedAt = block.timestamp;

        openDisputeForShipment[d.shipmentId] = 0;
        emit DisputeResolved(_disputeId, d.shipmentId, _resolution, _resolutionNote, msg.sender, block.timestamp);
        return true;
    }

    //view functions
    function getDispute(uint256 _disputeId) external view returns (Dispute memory) {
        require(_disputeId > 0 && _disputeId < _nextDisputeId, "Invalid disputeId");
        return disputes[_disputeId];
    }


    function getEvidenceCount(uint256 _disputeId) external view returns (uint256) {
        require(_disputeId > 0 && _disputeId < _nextDisputeId, "Invalid disputeId");
        return disputeEvidences[_disputeId].length;
    }

    function getEvidenceAtIndex(uint256 _disputeId, uint256 index) external view returns (Evidence memory) {
        require(index < disputeEvidences[_disputeId].length, "Index out of bounds");
        return disputeEvidences[_disputeId][index];
    }

}