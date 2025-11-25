// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowPayment.sol";
import "../src/Registration.sol";
import "../src/OracleManager.sol";
import "../src/ShipmentToken.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract EscrowPaymentTest is Test {
    using MessageHashUtils for bytes32;
    Registration reg;
    OracleManager om;
    ShipmentToken shipmentToken;
    EscrowPayment escrow;
    ERC20Mock token;
    address farmer;
    address transporter;
    address payer;
    address owner;

    function setUp() public {
        // Deploy contracts
        owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        om = new OracleManager(address(reg));
        shipmentToken = new ShipmentToken(address(reg), address(om), "Shipment", "SHP");
        escrow = new EscrowPayment(owner, address(shipmentToken)); // owner is platform receiver
        vm.stopPrank();

        // Setup test accounts
        farmer = makeAddr("farmer");
        transporter = makeAddr("transporter");
        payer = makeAddr("payer");

        // Register participants
        vm.prank(farmer);
        reg.registerParticipant(Registration.Role.FARMER, "farmerMeta");
        vm.prank(transporter);
        reg.registerParticipant(Registration.Role.TRANSPORTER, "transporterMeta");
        vm.prank(payer);
        reg.registerParticipant(Registration.Role.INDUSTRY, "payerMeta");

        // Setup KYC verification
        vm.prank(owner);
        reg.setKycStatus(farmer, Registration.KYCStatus.VERIFIED);
        vm.prank(owner);
        reg.setKycStatus(transporter, Registration.KYCStatus.VERIFIED);
        vm.prank(owner);
        reg.setKycStatus(payer, Registration.KYCStatus.VERIFIED);

        // Setup ERC20 token
        token = new ERC20Mock();
    }

    function testDepositAndReleaseByManager() public {
        bytes32 shipmentId = keccak256("shipment1");
        uint256 amount = 1e18;

        // Mint and approve tokens
        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(escrow), amount);

        // Deposit payment
        vm.prank(payer);
        escrow.depositPayment(shipmentId, address(token), amount, farmer, transporter, 7000, 2000, 1000);

        // Create shipment in ShipmentToken
        vm.prank(farmer);
        shipmentToken.createShipment(shipmentId, "metadata");
        vm.prank(farmer);
        shipmentToken.setIndustry(shipmentId, payer);
        vm.prank(farmer);
        shipmentToken.assignTransporter(shipmentId, transporter);

        // Set manager and release
        vm.prank(owner);
        escrow.setManager(address(this), true);
        escrow.releasePayment(shipmentId);

        // Verify balances and status
        assertEq(token.balanceOf(farmer), (amount * 7000) / 10000, "Incorrect farmer payment");
        assertEq(token.balanceOf(transporter), (amount * 2000) / 10000, "Incorrect transporter payment");
        assertEq(token.balanceOf(owner), (amount * 1000) / 10000, "Incorrect platform payment");
        
        EscrowPayment.Escrow memory e = escrow.getEscrow(shipmentId);
        assertEq(uint(e.status), uint(EscrowPayment.EscrowStatus.RELEASED), "Incorrect escrow status");
    }

    function testReleaseByFarmerAfterVerification() public {
        bytes32 shipmentId = keccak256("shipment2");
        uint256 amount = 1e18;

        // Setup shipment and payment
        vm.prank(farmer);
        shipmentToken.createShipment(shipmentId, "metadata");
        vm.prank(farmer);
        shipmentToken.setIndustry(shipmentId, payer);
        vm.prank(farmer);
        shipmentToken.assignTransporter(shipmentId, transporter);

        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(escrow), amount);
        vm.prank(payer);
        escrow.depositPayment(shipmentId, address(token), amount, farmer, transporter, 7000, 2000, 1000);

        // Register oracle and update state
        address oracle = makeAddr("oracle");
        vm.startPrank(owner);
        reg.registerTrustedParticipant(oracle, Registration.Role.ORACLE, "oracleMetaHash");
        om.addOracle(oracle, "oracleMetaHash");
        escrow.setManager(address(shipmentToken), true);
        vm.stopPrank();
        
        // Progress through states: ASSIGNED -> IN_TRANSIT -> DELIVERED -> VERIFIED
        (, uint256 oraclePrivateKey) = makeAddrAndKey("oracle");
        
        // IN_TRANSIT
        {
            uint256 nonce = 1;
            uint256 timestamp = block.timestamp;
            bytes32 hash = keccak256(abi.encode(
                block.chainid,
                shipmentId,
                uint8(ShipmentToken.ShipmentState.IN_TRANSIT),
                timestamp,
                nonce
            ));
            bytes32 ethSignedMessageHash = hash.toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
            bytes memory signature = abi.encodePacked(r, s, v);

            vm.prank(oracle);
            shipmentToken.updateShipmentState(ShipmentToken.StateInput({
                shipmentId: shipmentId,
                newState: ShipmentToken.ShipmentState.IN_TRANSIT,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature
            }));
        }

        // DELIVERED
        {
            uint256 nonce = 2;
            uint256 timestamp = block.timestamp;
            bytes32 hash = keccak256(abi.encode(
                block.chainid,
                shipmentId,
                uint8(ShipmentToken.ShipmentState.DELIVERED),
                timestamp,
                nonce
            ));
            bytes32 ethSignedMessageHash = hash.toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
            bytes memory signature = abi.encodePacked(r, s, v);

            vm.prank(oracle);
            shipmentToken.updateShipmentState(ShipmentToken.StateInput({
                shipmentId: shipmentId,
                newState: ShipmentToken.ShipmentState.DELIVERED,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature
            }));
        }

        // VERIFIED
        {
            uint256 nonce = 3;
            uint256 timestamp = block.timestamp;
            bytes32 hash = keccak256(abi.encode(
                block.chainid,
                shipmentId,
                uint8(ShipmentToken.ShipmentState.VERIFIED),
                timestamp,
                nonce
            ));
            bytes32 ethSignedMessageHash = hash.toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
            bytes memory signature = abi.encodePacked(r, s, v);

            vm.prank(oracle);
            shipmentToken.updateShipmentState(ShipmentToken.StateInput({
                shipmentId: shipmentId,
                newState: ShipmentToken.ShipmentState.VERIFIED,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature
            }));
        }

        // Farmer should now be able to release payment
        vm.prank(farmer);
        escrow.releasePayment(shipmentId);

        // Verify balances and status
        assertEq(token.balanceOf(farmer), (amount * 7000) / 10000, "Incorrect farmer payment");
        assertEq(token.balanceOf(transporter), (amount * 2000) / 10000, "Incorrect transporter payment");
        assertEq(token.balanceOf(owner), (amount * 1000) / 10000, "Incorrect platform payment");
        
        EscrowPayment.Escrow memory e = escrow.getEscrow(shipmentId);
        assertEq(uint(e.status), uint(EscrowPayment.EscrowStatus.RELEASED), "Incorrect escrow status");
    }

    function test_RevertWhen_ReleaseByFarmerBeforeVerification() public {
        bytes32 shipmentId = keccak256("shipment3");
        uint256 amount = 1e18;

        // Setup shipment and payment
        vm.prank(farmer);
        shipmentToken.createShipment(shipmentId, "metadata");
        vm.prank(farmer);
        shipmentToken.setIndustry(shipmentId, payer);

        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(escrow), amount);
        vm.prank(payer);
        escrow.depositPayment(shipmentId, address(token), amount, farmer, transporter, 7000, 2000, 1000);

        // Try to release before verification - should fail
        vm.prank(farmer);
        vm.expectRevert("Not authorized to release");
        escrow.releasePayment(shipmentId);
    }

    function testMockTransfer() public {
        token.mint(address(this), 1000);
        bool ok = token.transfer(address(0x1), 1000);
        assertTrue(ok);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0x1)), 1000);
    }
}
