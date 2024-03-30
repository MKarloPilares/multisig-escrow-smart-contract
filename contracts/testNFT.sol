// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

//Contract for minting test NFTs
contract testNFT is ERC721 {
    uint256 public nextTokenId;

    constructor() ERC721("MyNFT", "MNFT") {}

    function mint(address to) public {
        _safeMint(to, nextTokenId);
        nextTokenId++;
    }

        // Function to transfer NFT owned by this contract to another address
    function transferNFT(address _to, uint256 _tokenId) external {
        // Ensure the token is owned by this contract
        require(ownerOf(_tokenId) == address(this), "NFT not owned by this contract");

        // Transfer the NFT to the given address
        IERC721(0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9).approve(_to,_tokenId);
        IERC721(0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9).safeTransferFrom(address(this), _to,_tokenId);    
    }
}