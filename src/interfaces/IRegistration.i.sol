// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRegistration {
    // _role should be the numeric value of the enum Role from Registration.
    function hasRole(address _addr, uint8 _role) external view returns (bool);
    function isKycVerified(address _addr) external view returns (bool);
}
