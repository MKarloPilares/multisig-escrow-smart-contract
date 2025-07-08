// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./vTest.sol";
import "@openzeppelin/contracts/utils/Context.sol";

//Pawnshop Contract
contract NFTEscrow is Context, ReentrancyGuard, Ownable {
    struct Lock {
        address owner;
        uint256 tokenId;
        uint256 lockEndTime;
        uint256 bellsInside;
        bool active;
    }
    //Data structure for the lock corresponding to the received NFT
    
    event nftTaken(address indexed from, uint256 indexed tokenId, uint256 indexed bellsInside);
    event coinGiven(address indexed to, uint256 indexed coins);
    event nftReturned(address indexed to, uint256 tokenId);

    //Lock identifier mapping
    mapping(uint256 => Lock) public locks;
    
    // Add authorized operators mapping
    mapping(address => bool) public authorizedOperators;

    address public nftContractAddress;
    address public coinContractAddress;

    // Add events for admin actions
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event ContractAddressUpdated(address indexed oldAddress, address indexed newAddress, string contractType);

    modifier onlyAuthorized() {
        require(authorizedOperators[msg.sender] || msg.sender == owner(), "Not authorized");
       _;
    }

    modifier validTokenId(uint256 _tokenId) {
        require(_tokenId > 0, "Invalid token ID");
       _;
    }

    modifier lockExists(uint256 _tokenId) {
        require(locks[_tokenId].active, "Lock does not exist");
       _;
    }

    //Contract Address of NFT contract and Coin contract
    constructor() {
        nftContractAddress = 0xA3EB610e693fEE7EA8EaC77c43588F2D9D696Ed9;
        coinContractAddress = 0x220AF604194a7b991E8e0FEB05b4Ac028329b2dC;
        
        // Add deployer as initial authorized operator
        authorizedOperators[msg.sender] = true;
    }

    // Admin functions
    function addOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "Invalid operator address");
        authorizedOperators[_operator] = true;
        emit OperatorAdded(_operator);
    }

    function removeOperator(address _operator) external onlyOwner {
        authorizedOperators[_operator] = false;
        emit OperatorRemoved(_operator);
    }

    function updateNFTContract(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        address oldAddress = nftContractAddress;
        nftContractAddress = _newAddress;
        emit ContractAddressUpdated(oldAddress, _newAddress, "NFT");
    }

    function updateCoinContract(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        address oldAddress = coinContractAddress;
        coinContractAddress = _newAddress;
        emit ContractAddressUpdated(oldAddress, _newAddress, "Coin");
    }

    //Requests NFT from sender
    function takeNFT(uint256 _tokenId, uint256 bellsInside) external nonReentrant validTokenId(_tokenId) {
        require(bellsInside > 0, "Bells amount must be greater than 0");
        require(!locks[_tokenId].active, "NFT already locked");
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == msg.sender, "Not token owner");
        require(
            IERC721(nftContractAddress).getApproved(_tokenId) == address(this) || 
            IERC721(nftContractAddress).isApprovedForAll(msg.sender, address(this)),
            "Contract not approved"
        );

        //Calls NFT Contract transferFrom function to transfer NFT from sender address to contract
        IERC721(nftContractAddress).transferFrom(msg.sender, address(this), _tokenId);
        
        //Locks NFT for 5 minutes
        uint256 lockEndTime = block.timestamp + 5 minutes;
        
        //Makes new instance of Lock struct with tokenId as identifier
        locks[_tokenId] = Lock(msg.sender, _tokenId, lockEndTime, bellsInside, true);

        emit nftTaken(msg.sender, _tokenId, bellsInside);
    }

    //Gives Coins to original NFT owner based on inputted and checked Bells amount
    function giveCoins(uint256 _tokenId, uint256 bellsChecked) external nonReentrant onlyAuthorized lockExists(_tokenId) {
        require(bellsChecked > 0, "Bells amount must be greater than 0");
        //Bells checked needs to be same as inputted bells value
        require(bellsChecked == locks[_tokenId].bellsInside, "Bells Mismatch");
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == address(this), "NFT not in contract");
        
        address originalOwner = locks[_tokenId].owner;
        
        //Calls mint function of contract address
        VTest(coinContractAddress).mint(originalOwner, bellsChecked);

        emit coinGiven(originalOwner, bellsChecked);

        //Delete lock instance of NFT
        delete locks[_tokenId];
    }

    //Transfers NFT back to original owner
    function transferNFT(uint256 _tokenId) external nonReentrant lockExists(_tokenId) {
        Lock memory lock = locks[_tokenId];
        
        // Only original owner or authorized operators can call this after lock expires
        // Or original owner can call anytime
        require(
            msg.sender == lock.owner || 
            (authorizedOperators[msg.sender] && block.timestamp >= lock.lockEndTime),
            "Not authorized or lock still active"
        );
        
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == address(this), "NFT not in contract");

        // Transfer the NFT to the original owner
        IERC721(nftContractAddress).transferFrom(address(this), lock.owner, _tokenId);
        
        emit nftReturned(lock.owner, _tokenId);

        //Delete lock struct instance for NFT
        delete locks[_tokenId];
    }

    // Emergency function to recover stuck NFTs (only owner)
    function emergencyRecoverNFT(uint256 _tokenId, address _to) external onlyOwner {
        require(_to != address(0), "Invalid recipient");
        require(IERC721(nftContractAddress).ownerOf(_tokenId) == address(this), "NFT not in contract");
        
        IERC721(nftContractAddress).transferFrom(address(this), _to, _tokenId);
        
        // Clean up lock data if exists
        if (locks[_tokenId].active) {
            delete locks[_tokenId];
        }
    }

    // View function to check if lock is expired
    function isLockExpired(uint256 _tokenId) external view returns (bool) {
        if (!locks[_tokenId].active) return false;
        return block.timestamp >= locks[_tokenId].lockEndTime;
    }

    // View function to get remaining lock time
    function getRemainingLockTime(uint256 _tokenId) external view returns (uint256) {
        if (!locks[_tokenId].active) return 0;
        if (block.timestamp >= locks[_tokenId].lockEndTime) return 0;
        return locks[_tokenId].lockEndTime - block.timestamp;
    }
}