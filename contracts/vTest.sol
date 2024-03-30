// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ERC20 Contract initially owned by a wallet then will be transfered to the escrow contract after.
contract VTest is ERC20, Ownable  {
    constructor() ERC20("vTest", "VTS") Ownable(0x3fcc9F262124D96B48e03CC3683462C08049384E) {
    }

    //Mint function of the ERC20 contract
    function mint(address to, uint256 amount) public onlyOwner{
        _mint(to, amount);
    }

    //Burn function of the ERC20 contract
    function burn(address to, uint256 amount) public {
        _burn(to, amount);
    }
}