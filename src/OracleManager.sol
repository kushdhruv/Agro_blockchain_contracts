//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; //Using ECDSA signature verification for KYC attestations.
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IRegistration} from "./interfaces/IRegistration.i.sol";

contract OracleManager is Ownable{
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    uint8 public constant ADMIN_ROLE = 5;

    IRegistration public registration;

    struct Oracle {
        string metaDataHash; //IPFS hash reference to off-chain metadata
        uint256 createdAt;
        bool active;
    }

    mapping(address => Oracle) private _oracles;
    mapping(address => uint256) private _oracleIndex; //1-based index for easy iteration
    address[] private _oracleList;

    event RegistrationContractUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);
    event OracleAdded(address indexed oracleAddress, string metaDataHash, uint256 timestamp);
    event OracleUpdated(address indexed oracleAddress, string oldMetaDataHash, string newMetaDataHash, uint256 timestamp);
    event OracleRemoved(address indexed oracleAddress, uint256 timestamp);
    event OracleInactivate(address indexed oracleAddress, uint256 timestamp);
    event OracleActivated(address indexed oracleAddress, uint256 timestamp);


    constructor(address _registration) Ownable(msg.sender) {
        require(_registration != address(0), "Invalid registration address");
        registration = IRegistration(_registration);
    }

    modifier onlyAdminOrOwner() {
        require(registration.hasRole(msg.sender, ADMIN_ROLE) || msg.sender == owner(), "Only admin can perform this action");
        _;
    }

    function setRegistrationContract(address _registration) external onlyAdminOrOwner {
        require(_registration != address(0), "Invalid registration address");
        address oldAddress = address(registration);
        registration = IRegistration(_registration);
        emit RegistrationContractUpdated(oldAddress, _registration, block.timestamp);
    }

    // add oracle
    function addOracle(address _oracleAddress, string calldata _metaDataHash) external onlyAdminOrOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        require(!_oracles[_oracleAddress].active, "Oracle already exists");

        _oracles[_oracleAddress] = Oracle({
            metaDataHash: _metaDataHash,
            createdAt: block.timestamp,
            active: true
        });
        _oracleList.push(_oracleAddress);
        _oracleIndex[_oracleAddress] = _oracleList.length; //1-based index
        emit OracleAdded(_oracleAddress, _metaDataHash, block.timestamp);
    }

    // update oracle metadata
    function updateOracle(address _oracleAddress, string calldata _newMetaDataHash) external onlyAdminOrOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        require(_oracles[_oracleAddress].active, "Oracle is not active");
        string memory oldMetaDataHash = _oracles[_oracleAddress].metaDataHash;
        _oracles[_oracleAddress].metaDataHash = _newMetaDataHash;
        emit OracleUpdated(_oracleAddress, oldMetaDataHash, _newMetaDataHash, block.timestamp);
    }

    //remove oracle
    function removeOracle(address _oracleAddress) external onlyAdminOrOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        require(_oracleIndex[_oracleAddress] != 0, "Oracle index not found");

        // Remove from mapping
        delete _oracles[_oracleAddress];

        // Remove from list and index mapping(swap & pop method)
        uint256 index = _oracleIndex[_oracleAddress] - 1; // Convert to 0-based index
        uint256 lastIndex = _oracleList.length - 1;
        if (index != lastIndex) {
            address lastOracle = _oracleList[lastIndex];
            _oracleList[index] = lastOracle;
            _oracleIndex[lastOracle] = index + 1; 
        }
        _oracleList.pop();
        delete _oracleIndex[_oracleAddress];
        emit OracleRemoved(_oracleAddress, block.timestamp);
    }

    // inactivate oracle (soft delete)
    function inactivateOracle(address _oracleAddress) external onlyAdminOrOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        require(_oracles[_oracleAddress].active, "Oracle does not exist");
        _oracles[_oracleAddress].active = false;
        emit OracleInactivate(_oracleAddress, block.timestamp);
    }
    // activate oracle
    function activateOracle(address _oracleAddress) external onlyAdminOrOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        require(!_oracles[_oracleAddress].active, "Oracle is already active");
        _oracles[_oracleAddress].active = true;
        emit OracleActivated(_oracleAddress, block.timestamp);
    }

//view functions
    function getOracle(address _oracleAddress) external view returns (Oracle memory,address) {
        require(_oracleAddress != address(0), "Invalid oracle address");
        return (_oracles[_oracleAddress],_oracleAddress);
    }

    function isOracle(address _oracleAddress) external view returns (bool) {
        return _oracles[_oracleAddress].active;
    }

    function oracleCount() external view returns (uint256) {
        return _oracleList.length;
    }

    function oracleAtIndex(uint256 index) external view returns (address) {
        require(index < _oracleList.length, "Index out of bounds");
        return _oracleList[index];
    }

        // -----------------------------------------
    // Verification helpers
    // -----------------------------------------


    /**
    * @notice Verify a raw payload (bytes) that was signed off-chain.
    * @dev The expected flow: off-chain oracle prepares a payload (struct packed bytes),
    * signs keccak256(payload) with eth_sign (i.e., signed message prefixed). On-chain
    * call this function with the same payload and signature. This function recovers
    * the signer and returns (isAuthorizedOracle, signerAddress).
    *
    * Example usage from other contracts:
    * (bool ok, address signer) = oracleManager.verifySignedPayload(payload, sig);
    * require(ok, "invalid oracle signature");
    */
    function verifySignedPayload(bytes calldata payload, bytes calldata signature) external view returns (bool, address) {
        bytes32 digest = keccak256(payload).toEthSignedMessageHash();
        address signer = digest.recover(signature);
        return (_oracles[signer].active, signer);
    }


    /**
    * @notice Verify a precomputed 32-byte hash that was signed by an oracle.
    * @dev If other contracts compute the hash themselves (save calldata/encoding gas),
    * they can call this function with that hash + signature.
    */
    function verifySignedHash(bytes32 hash, bytes calldata signature) external view returns (bool, address) {
        bytes32 digest = hash.toEthSignedMessageHash();
        address signer = digest.recover(signature);
        return (_oracles[signer].active, signer);
    }
}