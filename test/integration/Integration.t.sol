// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/Registration.sol";
import "../../src/OracleManager.sol";
import "../../src/ShipmentToken.sol";
import "../../src/EscrowPayment.sol";
import "../../src/DisputeManager.sol";


import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../utils/KYCTestHelper.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract IntegrationTest is Test {
    function _assertPaymentSplits(ERC20Mock erc20Token, Participants memory p, address platformReceiver, uint256 amount) internal view {
        uint256 farmerAmt = (amount * 8000) / 10000;
        uint256 transporterAmt = (amount * 1500) / 10000;
        uint256 platformAmt = amount - farmerAmt - transporterAmt;
        assertEq(erc20Token.balanceOf(p.farmer), farmerAmt);
        assertEq(erc20Token.balanceOf(p.transporter), transporterAmt);
        assertEq(erc20Token.balanceOf(platformReceiver), platformAmt);
    }
    // (keep only one set of declarations, remove duplicates)

    function _updateShipmentState(
        address relayer,
        bytes32 shipmentId,
        ShipmentToken.ShipmentState newState,
        uint256 ts,
        uint256 nonce
    ) internal {
        bytes32 payloadState = keccak256(abi.encode(block.chainid, shipmentId, newState, ts, nonce)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oracleKey, payloadState);
        bytes memory sig = abi.encodePacked(r, s, v);
        ShipmentToken.StateInput memory stateInput = ShipmentToken.StateInput({
            shipmentId: shipmentId,
            newState: newState,
            timestamp: ts,
            nonce: nonce,
            signature: sig
        });
        vm.prank(relayer);
        st.updateShipmentState(stateInput);
    }
    struct Participants {
        address farmer;
        address transporter;
        address payer;
    }
    using MessageHashUtils for bytes32;
    Registration reg;
    OracleManager om;
    ShipmentToken st;
    EscrowPayment escrow;
    DisputeManager dm;
    KYCTestHelper kycHelper;
    ERC20Mock token;

    address owner;
    address oracle;
    uint256 oracleKey;

    function setUp() public {
        // deploy all core contracts as owner
        owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        om = new OracleManager(address(reg));
        st = new ShipmentToken(address(reg), address(om), "Shipment", "SHP");
        escrow = new EscrowPayment(owner, address(st)); // platform receiver = owner
        dm = new DisputeManager(address(reg), address(escrow), address(om));
        vm.stopPrank();

        // helper registers a KYC signer and wires it in Registration
        kycHelper = new KYCTestHelper(reg, owner);

        // create an oracle with a private key and register it
        (oracle, oracleKey) = makeAddrAndKey("oracleKey");
        vm.startPrank(owner);
        reg.registerTrustedParticipant(oracle, Registration.Role.ORACLE, "oracleMetaHash");
        om.addOracle(oracle, "oracleMetaHash");
        vm.stopPrank();

        // set escrow managers (ShipmentToken and DisputeManager will act as managers)
        vm.prank(owner);
        escrow.setManager(address(st), true);
        vm.prank(owner);
        escrow.setManager(address(dm), true);

        // prepare ERC20 token
        token = new ERC20Mock();
    }

    function test_fullShipmentPaymentFlow() public {
        Participants memory p;
        p.farmer = makeAddr("farmer");
        p.transporter = makeAddr("transporter");
        p.payer = makeAddr("industry");

        // owner registers participants
        vm.prank(p.farmer);
        reg.registerParticipant(Registration.Role.FARMER, "farmerMeta");
        vm.prank(p.transporter);
        reg.registerParticipant(Registration.Role.TRANSPORTER, "transporterMeta");
        vm.prank(p.payer);
        reg.registerParticipant(Registration.Role.INDUSTRY, "payerMeta");

        // KYC attestation for farmer/transporter/payer using kycHelper signer
        // (the one that actually signs the params)
        Registration.KYCAttestationParams memory kycParams;
        kycParams = kycHelper.createKYCParams(p.farmer, Registration.Role.FARMER, "meta", block.timestamp, 1);
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(kycParams);

        kycParams = kycHelper.createKYCParams(p.transporter, Registration.Role.TRANSPORTER, "meta", block.timestamp, 2);
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(kycParams);

        kycParams = kycHelper.createKYCParams(p.payer, Registration.Role.INDUSTRY, "meta", block.timestamp, 3);
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(kycParams);

        // farmer creates shipment
        bytes32 shipmentId = keccak256(abi.encodePacked("shipment-1"));
            vm.prank(p.farmer);
    st.createShipment(shipmentId, "ipfs://meta1");
    // Set industry before assigning transporter
    vm.prank(p.farmer);
    st.setIndustry(shipmentId, p.payer);
    // Assign transporter before state updates
    vm.prank(p.farmer);
    st.assignTransporter(shipmentId, p.transporter);

    // payer mints and deposits token
    uint256 amount = 1e18;
        token.mint(p.payer, amount);
        vm.prank(p.payer);
    token.approve(address(escrow), amount);

    // deposit split 80% farmer, 15% transporter, 5% platform
        vm.prank(p.payer);
    escrow.depositPayment(shipmentId, address(token), amount, p.farmer, p.transporter, 8000, 1500, 500);

        // simulate shipping start: ShipmentToken (as manager) holds payment
        vm.prank(address(st));
        escrow.holdPayment(shipmentId);

        // prepare and attach an oracle-signed proof
        uint256 ts = block.timestamp;
        uint256 nonce = 1;
    bytes32 payload = keccak256(abi.encode(block.chainid, shipmentId, uint8(0), keccak256(bytes("proof-hash")), ts, nonce)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oracleKey, payload);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Use oracle as relayer since they need to be authorized
        ShipmentToken.ProofInput memory proofInput = ShipmentToken.ProofInput({
            shipmentId: shipmentId,
            proofType: ShipmentToken.ProofType.GENERIC,
            proofHash: "proof-hash",
            timestamp: ts,
            nonce: nonce,
            signature: sig
        });
        vm.prank(oracle);
        st.attachProof(proofInput);

        // update state to IN_TRANSIT then DELIVERED then VERIFIED (signed by oracle)
        // State transitions: IN_TRANSIT -> DELIVERED -> VERIFIED
        for (uint8 i = 2; i <= 4; i++) {
            ShipmentToken.ShipmentState newState = ShipmentToken.ShipmentState(i);
            _updateShipmentState(oracle, shipmentId, newState, ts, i+1); // nonce starts at 3
        }

    // Now release payment (ShipmentToken as manager calls release)
    // Ensure preconditions: escrow manager already set to st
    // Check balances before
        assertEq(token.balanceOf(p.farmer), 0);
        assertEq(token.balanceOf(p.transporter), 0);
        assertEq(token.balanceOf(owner), 0); // platform receiver

    vm.prank(address(st));
    escrow.releasePayment(shipmentId);

    // compute expected splits and assert balances
    _assertPaymentSplits(token, p, owner, amount);

        // escrow status updated
        EscrowPayment.Escrow memory e = escrow.getEscrow(shipmentId);
        assertEq(uint(e.status), uint(EscrowPayment.EscrowStatus.RELEASED));
    }

    function test_disputeRaisesAndHolds() public {
        // Reuse simpler setup: create a fresh shipment and attempt dispute
        address farmer = makeAddr("farmer2");
        address payer = makeAddr("industry2");

        vm.prank(farmer);
        reg.registerParticipant(Registration.Role.FARMER, "fm2");
        vm.prank(payer);
        reg.registerParticipant(Registration.Role.INDUSTRY, "pay2");

        // KYC for both
        Registration.KYCAttestationParams memory ap1 = kycHelper.createKYCParams(farmer, Registration.Role.FARMER, "meta", block.timestamp, 21);
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(ap1);

        Registration.KYCAttestationParams memory ap2 = kycHelper.createKYCParams(payer, Registration.Role.INDUSTRY, "meta", block.timestamp, 22);
        vm.prank(kycHelper.kycSigner());
        reg.kycAttestation(ap2);

        bytes32 sId = keccak256(abi.encodePacked("s2"));
        vm.prank(farmer);
        st.createShipment(sId, "meta2");

        // payer deposits
        uint256 amount = 1000;
        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(escrow), amount);
        vm.prank(payer);
        escrow.depositPayment(sId, address(token), amount, farmer, address(0), 10000, 0, 0);

        // now raise dispute by farmer (onlyKyc)
        vm.prank(farmer);
        uint256 id = dm.raiseDispute(sId, "evidence1");
        assertTrue(id > 0);

        // If DisputeManager was authorized as manager, escrow should be held; verify status is HELD or still DEPOSITED depending on manager setup
        EscrowPayment.Escrow memory esc = escrow.getEscrow(sId);
        // status should be HELD because we added dm as manager in setUp
        assertEq(uint(esc.status), uint(EscrowPayment.EscrowStatus.HELD));
    }
}
