// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./vTest.sol";
import "@openzeppelin/contracts/utils/Context.sol";

//Pawnshop Contract
contract MultiSigNFTEscrow is Context, ReentrancyGuard, Ownable {
    //Data structure for the lock corresponding to the received NFT
    
    event nftTaken(address indexed from, uint256 indexed tokenId, uint256 indexed bellsInside);
    event coinGiven(address indexed to, uint256 indexed coins);
    event nftReturned(address indexed to, uint256 tokenId);

    address public nftContractAddress;
    address public coinContractAddress;
    address public backEndAddress;
    
    // Add nonce mapping to prevent replay attacks
    mapping(address => uint256) public nonces;
    
    // Add struct for pawn data to ensure signature verification
    struct PawnData {
        uint256 tokenId;
        uint256 bellsAmount;
        address owner;
        uint256 nonce;
    }

    //Contract Address of NFT contract and Coin contract
    constructor() {
        nftContractAddress = 0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9;
        coinContractAddress = 0x45644b734E10B710B3cEa0cEd94cC4A33bbbe161;
        backEndAddress = 0x3fcc9F262124D96B48e03CC3683462C08049384E;
    }
    
    // Add function to update addresses (only owner)
    function updateAddresses(address _nft, address _coin, address _backend) external onlyOwner {
        require(_nft != address(0) && _coin != address(0) && _backend != address(0), "Invalid addresses");
        nftContractAddress = _nft;
        coinContractAddress = _coin;
        backEndAddress = _backend;
    }

    function pawn(uint256 _tokenId, uint256 bellsInside, 
    bytes32 custMessHash, bytes32 apiMessHash,
    uint8 vCust, bytes32 rCust, bytes32 sCust,
    uint8 vApi, bytes32 rApi, bytes32 sApi
    ) external nonReentrant {
        require(_tokenId > 0, "Invalid token ID");
        require(bellsInside > 0, "Invalid bells amount");
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == msg.sender, "Not token owner");
        require(IERC721(nftContractAddress).getApproved(_tokenId) == address(this) || 
                IERC721(nftContractAddress).isApprovedForAll(msg.sender, address(this)), "Contract not approved");
        
        // Create expected message hash for verification
        bytes32 expectedCustHash = keccak256(abi.encodePacked(_tokenId, bellsInside, msg.sender, nonces[msg.sender]));
        bytes32 expectedApiHash = keccak256(abi.encodePacked(_tokenId, bellsInside, msg.sender, nonces[msg.sender]));
        
        // Verify the provided hashes match expected hashes
        require(custMessHash == expectedCustHash, "Invalid customer message hash");
        require(apiMessHash == expectedApiHash, "Invalid API message hash");
        
        bytes32 prefixedCustMessHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", custMessHash));
        bytes32 prefixedApiMessHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", apiMessHash));

        address signerCust = ecrecover(prefixedCustMessHash, vCust, rCust, sCust);
        address signerApi = ecrecover(prefixedApiMessHash, vApi, rApi, sApi);
        
        require(signerCust == msg.sender, "Invalid customer signature");
        require(signerApi == backEndAddress, "Invalid API signature");
        
        // Increment nonce to prevent replay attacks
        nonces[msg.sender]++;

        takeNFT(_tokenId);
        giveCoins(_tokenId, bellsInside);
    }

        //Requests  NFT from sender
    function takeNFT(uint256 _tokenId) private {
        //Calls NFT Contract transferFrom function to transfer NFT from sender address to contract
        IERC721(nftContractAddress).transferFrom(msg.sender, address(this), _tokenId);
        emit nftTaken(msg.sender, _tokenId, 0); // Emit event
    }

        //Gives Coins to original NFT owner based on inputted and checked Bells amount
    function giveCoins(uint256 _tokenId, uint256 bellsChecked) private {
        address takenNftOwner = IERC721(nftContractAddress).ownerOf(_tokenId);
        require(takenNftOwner == address(this), "NFT not in contract");
        
        VTest(coinContractAddress).mint(msg.sender, bellsChecked);
        emit coinGiven(msg.sender, bellsChecked); // Emit event
    }

        //Transfers NFT back to original owner - should be public for emergency cases
    function giveBackNft(uint256 _tokenId) external nonReentrant {
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == address(this), "NFT not in contract");
        // Add logic to verify caller is original owner or authorized
        
        // Transfer the NFT to the original owner
        IERC721(nftContractAddress).transferFrom(address(this), msg.sender, _tokenId);
        emit nftReturned(msg.sender, _tokenId); // Emit event
    }
    
    // Emergency function to recover stuck NFTs (only owner)
    function emergencyRecoverNFT(uint256 _tokenId, address _to) external onlyOwner {
        require(_to != address(0), "Invalid recipient");
        IERC721(nftContractAddress).transferFrom(address(this), _to, _tokenId);
    }
}
