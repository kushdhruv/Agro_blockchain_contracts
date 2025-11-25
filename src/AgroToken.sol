// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AgroToken is ERC20, Ownable {
    constructor() ERC20("AgroToken", "AGT") Ownable(msg.sender) {
        // Mint 1 million tokens to deployer with 18 decimals
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    /**
     * @dev Mint new tokens (only owner)
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
