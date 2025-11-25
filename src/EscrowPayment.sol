//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IShipmentToken} from "./interfaces/IShipmentToken.i.sol";

/**
* @title EscrowPayment
* @notice Simple escrow manager for shipment payments using ERC-20 tokens.
* - Industry (payer) deposits funds tied to a shipmentId.
* - Deposit must include expected split percentages for farmer/transporter/platform in basis points (out of 10000).
* - Authorized managers (ShipmentToken, DisputeManager, Gov multisig) can hold/release/refund funds.
*
* Design choices:
* - Keep the contract minimal but safe (reentrancy guard, SafeERC20).
* - Require that the depositor provides the farmer address and verify it again  st on-chain ownership
* (ownerOf(tokenId)) by calling the ShipmentToken ERC721 contract. This avoids tight coupling to
* a ShipmentToken-specific getter API.
* - Percentages are expressed in basis points (bps) where 10000 == 100%.
*/

contract EscrowPayment is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint16 public constant MAX_BPS = 10000; //100%
    enum EscrowStatus { NONE, DEPOSITED , HELD, RELEASED, REFUNDED }
    address public platformAddress; //platform fee recipient
    address public shipmentToken; // ShipmentToken contract reference
    uint256 public cancellationPeriod = 1 hours; // default cancellation window after deposit


    struct Escrow {
        address token; //ERC-20 token address
        uint256 amount;
        address payer;
        address farmer;
        address transporter;
        uint16 farmerBps; //in basis points (out of 10000)
        uint16 transporterBps;
        uint16 platformBps;
        EscrowStatus status;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(address => bool) public authorizedManagers; //ShipmentToken, DisputeManager, Gov multisig
    mapping(bytes32 => Escrow) private escrows;

    event PlatformReceiverUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);
    event ShipmentTokenUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);
    event ManagerUpdated(address indexed manager, bool authorized, uint256 timestamp);
    event PaymentDeposited(bytes32 indexed shipmentId, address indexed payer, address indexed token, uint256 amount, address farmer, address transporter, uint16 farmerBps, uint16 transporterBps, uint16 platformBps, uint256 timestamp);
    event PaymentHeld(bytes32 indexed shipmentId, uint256 timestamp);
    event PaymentReleased(bytes32 indexed shipmentId, uint256 farmerAmount, uint256 transporterAmount, uint256 platformAmount, uint256 timestamp);
    event PaymentRefunded(bytes32 indexed shipmentId, uint256 amount, uint256 timestamp);
    event PaymentCancelled(bytes32 indexed shipmentId, address indexed payer, uint256 amount, uint256 timestamp);

    constructor(
        address _platformReceiver,
        address _shipmentToken
    ) Ownable(msg.sender) {
        require(_platformReceiver != address(0), "Invalid platform address");
        require(_shipmentToken != address(0), "Invalid shipment token address");
        platformAddress = _platformReceiver;
        shipmentToken = _shipmentToken;
    }

    modifier onlyAuthorizedManager() {
        require(authorizedManagers[msg.sender], "Not an authorized manager");
        _;
    }

    //admin functions

    function setPlatformReceiver(address _receiver) external onlyOwner{
        require(_receiver != address(0), "Invalid address");
        address old = platformAddress;
        platformAddress = _receiver;
        emit PlatformReceiverUpdated(old,_receiver,block.timestamp);
    }

    /// @notice Emergency function to update shipment token address in case of upgrades
    /// @dev Should only be used when deploying new version of ShipmentToken
    function setShipmentToken(address _shipmentToken) external onlyOwner {
        require(_shipmentToken != address(0), "Invalid address");
        address old = shipmentToken;
        shipmentToken = _shipmentToken;
        emit ShipmentTokenUpdated(old, _shipmentToken, block.timestamp);
    }

    function setManager(address _manager, bool _authorized) external onlyOwner {
        require(_manager != address(0), "Invalid manager address");
        authorizedManagers[_manager] = _authorized;

        emit ManagerUpdated(_manager, _authorized, block.timestamp); 
    }

    /// @notice Set the cancellation window (seconds)
    function setCancellationPeriod(uint256 _seconds) external onlyOwner {
        cancellationPeriod = _seconds;
    }

    //core:deposits

    function depositPayment(
        bytes32 _shipmentId,
        address _token,
        uint256 _amount,
        address _farmer,
        address _transporter,
        uint16 _farmerBps,
        uint16 _transporterBps,
        uint16 _platformBps
    ) external nonReentrant {
        require(_shipmentId != bytes32(0), "Invalid shipmentId");
        require(escrows[_shipmentId].status == EscrowStatus.NONE,"Escrow already exists");
        require(_token != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than zero");
        require(_farmer != address(0), "Invalid farmer address");
        
        uint256 totalBps = uint256(_farmerBps) + uint256(_transporterBps) + uint256(_platformBps);
        require(totalBps == MAX_BPS, "Invalid BPS total");

        //transfer tokens from payer to escrow
        IERC20 token = IERC20(_token);
        uint256 beforeTransfer = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterTransfer = token.balanceOf(address(this));
        uint256 received = afterTransfer - beforeTransfer;
        require(received > 0, "No tokens transferred");

        escrows[_shipmentId] = Escrow({
            token: _token,
            amount: received, // Store actual received amount to support fee-on-transfer tokens
            payer: msg.sender,
            farmer: _farmer,
            transporter: _transporter,
            farmerBps: _farmerBps,
            transporterBps: _transporterBps,
            platformBps: _platformBps,
            status: EscrowStatus.DEPOSITED,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        emit PaymentDeposited(_shipmentId, msg.sender, _token, _amount, _farmer, _transporter, _farmerBps, _transporterBps, _platformBps, block.timestamp);
    }

    //hold funds - only authorized managers
    function holdPayment(bytes32 _shipmentId) external onlyAuthorizedManager {
        Escrow storage e = escrows[_shipmentId];
        require(e.status == EscrowStatus.DEPOSITED, "Escrow not in DEPOSITED status");
        e.status = EscrowStatus.HELD;
        e.updatedAt = block.timestamp;

        emit PaymentHeld(_shipmentId, block.timestamp);
    }

    //release funds - can be called by authorized managers or farmer after verification
    function releasePayment(bytes32 _shipmentId) external nonReentrant {
        Escrow storage e = escrows[_shipmentId];
        require(e.status == EscrowStatus.DEPOSITED || e.status == EscrowStatus.HELD, "Escrow not in releasable status");
        
        // Check if caller is authorized manager or the farmer after shipment verification
        bool isManager = authorizedManagers[msg.sender];
        bool isVerifiedShipment = IShipmentToken(shipmentToken).isShipmentVerified(_shipmentId);
        bool isFarmer = msg.sender == e.farmer;
        
        require(isManager || (isFarmer && isVerifiedShipment), "Not authorized to release");

        uint256 totalAmount = e.amount;
        uint256 farmerAmount = (totalAmount * e.farmerBps) / MAX_BPS;
        uint256 transporterAmount = (totalAmount * e.transporterBps) / MAX_BPS;
        uint256 platformAmount = totalAmount - farmerAmount - transporterAmount; //remaining amount to avoid rounding issues

        //transfer funds
        require(farmerAmount + transporterAmount + platformAmount == totalAmount,"Amount mismatch");

        if(farmerAmount > 0){
            IERC20(e.token).safeTransfer(e.farmer, farmerAmount);
        }
        if(transporterAmount > 0 && e.transporter != address(0)){
            IERC20(e.token).safeTransfer(e.transporter, transporterAmount);
        }
        if(platformAmount > 0){
            IERC20(e.token).safeTransfer(platformAddress, platformAmount);
        }

        e.status = EscrowStatus.RELEASED;
        e.updatedAt = block.timestamp;

        emit PaymentReleased(_shipmentId, farmerAmount, transporterAmount, platformAmount, block.timestamp);
    }

    //refund funds - only authorized managers
    function refundPayment(bytes32 _shipmentId) external nonReentrant onlyAuthorizedManager {
        Escrow storage e = escrows[_shipmentId];
        require(e.status == EscrowStatus.DEPOSITED || e.status == EscrowStatus.HELD, "Escrow not in refundable status");

        uint256 amount = e.amount;
        require(amount > 0, "No amount to refund");

        IERC20(e.token).safeTransfer(e.payer, amount);
        e.status = EscrowStatus.REFUNDED;
        e.updatedAt = block.timestamp;

        emit PaymentRefunded(_shipmentId, amount, block.timestamp);
    }

    /// @notice Allow payer to cancel and refund only within `cancellationPeriod` and only if still DEPOSITED.
    /// @dev Managers should mark escrow HELD when shipping/progress begins; cancellation window prevents mid-process cancellations.
    function cancelByPayer(bytes32 _shipmentId) external nonReentrant {
        Escrow storage e = escrows[_shipmentId];
        require(e.status == EscrowStatus.DEPOSITED, "Not refundable");
        require(msg.sender == e.payer, "Only payer can cancel");
        require(block.timestamp <= e.createdAt + cancellationPeriod, "Cancellation window passed");

        uint256 amount = e.amount;
        require(amount > 0, "No amount to refund");

        // update state before external call
        e.amount = 0;
        e.status = EscrowStatus.REFUNDED;
        e.updatedAt = block.timestamp;

        IERC20(e.token).safeTransfer(e.payer, amount);

        emit PaymentCancelled(_shipmentId, e.payer, amount, block.timestamp);
        emit PaymentRefunded(_shipmentId, amount, block.timestamp); // optional duplicate event for compatibility
    }

    //view functions
    function getEscrow(bytes32 _shipmentId) external view returns (Escrow memory) {
        return escrows[_shipmentId];
    }

    function isAuthorizedManager(address _addr) external view returns (bool) {
        return authorizedManagers[_addr];
    }

}