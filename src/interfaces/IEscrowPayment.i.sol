//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrowPayment{
    function holdPayment(bytes32 _shipmentId) external;
    function releasePayment(bytes32 _shipmentId) external;
    function refundPayment(bytes32 _shipmentId) external;
}