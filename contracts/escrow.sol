// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./vTest.sol";
import "@openzeppelin/contracts/utils/Context.sol";

//Pawnshop Contract
contract NFTEscrow is Context{
        struct Lock {
        address owner;
        uint256 tokenId;
        uint256 lockEndTime;
        uint256 bellsInside;
    }
    //Data structure for the lock corresponding to the received NFT
    
    event nftTaken(address indexed from, uint256 indexed tokenId, uint256 indexed bellsInside);
    event coinGiven(address indexed to, uint256 indexed coins);
    event nftReturned(address indexed to, uint256 tokenId);

    //Lock identifier mapping
    mapping(uint256 => Lock) public locks;

    address public nftContractAddress;
    address public coinContractAddress;

    //Contract Address of NFT contract and Coin contract
    constructor() {
        nftContractAddress = 0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9;
        coinContractAddress = 0x220AF604194a7b991E8e0FEB05b4Ac028329b2dC;
    }

    //Requests  NFT from sender
    function takeNFT(uint256 _tokenId, uint256 bellsInside) external {
        //Calls NFT Contract transferFrom function to transfer NFT from sender address to contract
        IERC721(nftContractAddress).transferFrom(msg.sender, address(this), _tokenId);
        //Locks NFT for 5 minutes
        uint256 lockEndTime = block.timestamp + 5 minutes;
        
        //Makes new instance of Lock struct with tokenId as identifier
        locks[_tokenId] = Lock(msg.sender, _tokenId, lockEndTime, bellsInside);

        emit nftTaken(msg.sender, _tokenId, bellsInside);
    }

    //Gives Coins to original NFT owner based on inputted and checked Bells amount
    function giveCoins(uint256 _tokenId,uint256 bellsChecked) external {
        //Bells checked needs to be same as inputted bells value
        require(bellsChecked == locks[_tokenId].bellsInside, "Bells Mismatch");
        //Calls mint function of contract address
        VTest(coinContractAddress).mint(locks[_tokenId].owner, bellsChecked);

        emit coinGiven(locks[_tokenId].owner, bellsChecked);

        //Delete lock instance of NFT
        delete locks[_tokenId];
    }

    //Transfers NFT back to original owner
    function transferNFT(uint256 _tokenId) external {
        //Lock must have ended
        require(block.timestamp >= locks[_tokenId].lockEndTime, "Tokens still locked");

        // Transfer the NFT to the original owner
        IERC721(nftContractAddress).transferFrom(address(this), locks[_tokenId].owner, _tokenId);
        
        emit nftReturned(locks[_tokenId].owner, _tokenId);

        //Delete lock struct instance for NFT
        delete locks[_tokenId];
        
    }
}