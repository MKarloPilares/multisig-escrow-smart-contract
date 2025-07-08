// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}
    
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract ReentrancyAttacker {
    address public escrowContract;
    
    constructor(address _escrow) {
        escrowContract = _escrow;
    }
    
    function attack(uint256 tokenId, uint256 bellsAmount) external {
        // This would attempt reentrancy
        (bool success,) = escrowContract.call(
            abi.encodeWithSignature(
                "pawn(uint256,uint256,bytes32,bytes32,uint8,bytes32,bytes32,uint8,bytes32,bytes32)",
                tokenId, bellsAmount, bytes32(0), bytes32(0), 0, bytes32(0), bytes32(0), 0, bytes32(0), bytes32(0)
            )
        );
        require(success, "Attack failed");
    }
}
