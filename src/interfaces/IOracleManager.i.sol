// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracleManager {
    function verifySignedPayload(bytes calldata payload, bytes calldata signature) external view returns (bool, address);
    function verifySignedHash(bytes32 hash, bytes calldata signature) external view returns (bool, address);
    function isOracle(address oracle) external view returns (bool);
}
