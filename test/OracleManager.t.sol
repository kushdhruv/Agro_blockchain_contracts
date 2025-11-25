// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OracleManager.sol";
import "../src/Registration.sol";
import "./utils/KYCTestHelper.sol";

contract OracleManagerTest is Test {
    Registration reg;
    OracleManager om;
    KYCTestHelper kycHelper;

    function setUp() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        reg = new Registration();
        om = new OracleManager(address(reg));
        vm.stopPrank();
        kycHelper = new KYCTestHelper(reg, owner);
    }

    function testAddOracleAndVerify() public {
        address oracle = makeAddr("oracle1");
        vm.startPrank(kycHelper.owner());
        om.addOracle(oracle, "meta");
        vm.stopPrank();
        assertTrue(om.isOracle(oracle));
    }
}
