// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgroToken.sol";

contract DeployAgroToken is Script {
    function run() external {
        vm.startBroadcast();
        
        // Deploy AgroToken
        AgroToken token = new AgroToken();
        console.log("AgroToken deployed at:", address(token));
        
        // Anvil default accounts (first 10)
        address[10] memory accounts = [
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,  // Account 0 (deployer)
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,  // Account 1
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,  // Account 2
            0x90F79bf6EB2c4f870365E785982E1f101E93b906,  // Account 3
            0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,  // Account 4
            0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,  // Account 5
            0x976EA74026E726554dB657fA54763abd0C3a0aa9,  // Account 6
            0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,  // Account 7
            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,  // Account 8
            0xa0Ee7A142d267C1f36714E4a8F75612F20a79720   // Account 9
        ];
        
        // Mint 100,000 tokens to each account (for testing escrow payments)
        uint256 mintAmount = 100_000 * 10 ** 18;
        for (uint256 i = 0; i < 10; i++) {
            token.mint(accounts[i], mintAmount);
            console.log("Minted 100,000 AGT to:", accounts[i]);
        }
        
        vm.stopBroadcast();
    }
}
