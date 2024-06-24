// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./vTest.sol";
import "@openzeppelin/contracts/utils/Context.sol";

//Pawnshop Contract
contract MultiSigNFTEscrow is Context{
    //Data structure for the lock corresponding to the received NFT
    
    event nftTaken(address indexed from, uint256 indexed tokenId, uint256 indexed bellsInside);
    event coinGiven(address indexed to, uint256 indexed coins);
    event nftReturned(address indexed to, uint256 tokenId);

    address public nftContractAddress;
    address public coinContractAddress;
    address public backEndAddress;

    //Contract Address of NFT contract and Coin contract
    constructor() {
        nftContractAddress = 0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9;
        coinContractAddress = 0x45644b734E10B710B3cEa0cEd94cC4A33bbbe161;
        backEndAddress = 0x3fcc9F262124D96B48e03CC3683462C08049384E;
    }

    function pawn(uint256 _tokenId, uint256 bellsInside, 
    bytes32 custMessHash, bytes32 apiMessHash,
    uint8 vCust, bytes32 rCust, bytes32 sCust,
    uint8 vApi, bytes32 rApi, bytes32 sApi
    ) public  {
        bytes32 prefixedCustMessHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", custMessHash));
        bytes32 prefixedApiMessHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", apiMessHash));

        address signerCust = ecrecover(prefixedCustMessHash, vCust, rCust, sCust);

        address signerApi = ecrecover(prefixedApiMessHash, vApi, rApi, sApi);

        takeNFT(_tokenId);

        giveCoins(_tokenId, bellsInside, signerCust, signerApi);
        
    }

        //Requests  NFT from sender
    function takeNFT(uint256 _tokenId) private {
        //Calls NFT Contract transferFrom function to transfer NFT from sender address to contract
        IERC721(nftContractAddress).transferFrom(msg.sender, address(this), _tokenId);
    }

        //Gives Coins to original NFT owner based on inputted and checked Bells amount
    function giveCoins(uint256 _tokenId,uint256 bellsChecked, address signerCust, address signerApi) private {
        address takenNftOwner = IERC721(nftContractAddress).ownerOf(_tokenId);
        if (takenNftOwner == address(this)) {
            if (signerCust == msg.sender && signerApi == backEndAddress) {
                VTest(coinContractAddress).mint(msg.sender, bellsChecked);
            } else{
                giveBackNft(_tokenId);
            }
        }
    }

        //Transfers NFT back to original owner
    function giveBackNft(uint256 _tokenId) private {

        // Transfer the NFT to the original owner
        IERC721(nftContractAddress).transferFrom(address(this), msg.sender, _tokenId);
        
    }
}   
