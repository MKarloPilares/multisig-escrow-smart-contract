// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./vTest.sol";

/**
 * @title MultiSigNFTEscrow
 * @dev A secure pawnshop contract for NFT collateralized lending
 * @notice Allows users to pawn NFTs for tokens with multi-signature verification
 */
contract MultiSigNFTEscrow is ReentrancyGuard, Pausable, AccessControl, EIP712 {
    using ECDSA for bytes32;

    // Role definitions
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Contract state
    address public nftContractAddress;
    address public coinContractAddress;
    
    // User nonces for replay protection
    mapping(address => uint256) public nonces;
    
    // Pawn tracking
    mapping(uint256 => PawnInfo) public pawnedNFTs;
    mapping(address => uint256[]) public userPawnedTokens;
    
    // Configuration
    uint256 public constant MAX_PAWN_DURATION = 30 days;
    uint256 public constant MIN_PAWN_AMOUNT = 1e15; // 0.001 tokens minimum
    uint256 public maxPawnAmount = 1000e18; // 1000 tokens maximum
    uint256 public platformFeeRate = 250; // 2.5% (basis points)
    uint256 public constant MAX_FEE_RATE = 1000; // 10% maximum
    
    // Fee collection
    address public feeCollector;
    uint256 public collectedFees;

    // Structs
    struct PawnInfo {
        address owner;
        uint256 bellsAmount;
        uint256 pawnTime;
        uint256 expiryTime;
        bool active;
        uint256 feesPaid;
    }

    struct PawnSignature {
        uint256 tokenId;
        uint256 bellsAmount;
        address owner;
        uint256 nonce;
        uint256 deadline;
    }

    // Type hash for EIP712
    bytes32 public constant PAWN_TYPEHASH = keccak256(
        "PawnSignature(uint256 tokenId,uint256 bellsAmount,address owner,uint256 nonce,uint256 deadline)"
    );

    // Events
    event NFTPawned(
        address indexed user,
        uint256 indexed tokenId,
        uint256 bellsAmount,
        uint256 fees,
        uint256 expiryTime
    );
    
    event NFTRedeemed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 bellsAmount
    );
    
    event NFTLiquidated(
        address indexed user,
        uint256 indexed tokenId,
        uint256 bellsAmount
    );
    
    event ContractAddressUpdated(
        string indexed contractType,
        address indexed oldAddress,
        address indexed newAddress
    );
    
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesWithdrawn(address indexed collector, uint256 amount);
    event EmergencyWithdrawal(uint256 indexed tokenId, address indexed to);

    // Custom errors
    error InvalidTokenId();
    error InvalidBellsAmount();
    error NotTokenOwner();
    error ContractNotApproved();
    error InvalidSignature();
    error SignatureExpired();
    error NFTNotPawned();
    error NFTAlreadyPawned();
    error PawnExpired();
    error PawnNotExpired();
    error InvalidAddress();
    error ExceedsMaxAmount();
    error InsufficientAmount();
    error InvalidFeeRate();

    // Modifiers
    modifier validTokenId(uint256 _tokenId) {
        if (_tokenId == 0) revert InvalidTokenId();
       _;
    }

    modifier onlyNFTOwner(uint256 _tokenId) {
        if (IERC721(nftContractAddress).ownerOf(_tokenId) != msg.sender) {
            revert NotTokenOwner();
        }
       _;
    }

    modifier pawnExists(uint256 _tokenId) {
        if (!pawnedNFTs[_tokenId].active) revert NFTNotPawned();
       _;
    }

    constructor(
        address _nftContract,
        address _coinContract,
        address _feeCollector
    ) EIP712("MultiSigNFTEscrow", "1") {
        if (_nftContract == address(0) || _coinContract == address(0) || _feeCollector == address(0)) {
            revert InvalidAddress();
        }
        
        nftContractAddress = _nftContract;
        coinContractAddress = _coinContract;
        feeCollector = _feeCollector;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    /**
     * @notice Pawn an NFT for tokens with multi-signature verification
     * @param pawnData The pawn transaction data
     * @param userSignature User's signature
     * @param backendSignature Backend's signature
     */
    function pawnNFT(
        PawnSignature calldata pawnData,
        bytes calldata userSignature,
        bytes calldata backendSignature
    ) external nonReentrant whenNotPaused validTokenId(pawnData.tokenId) {
        // Validate pawn data
        _validatePawnData(pawnData);
        
        // Verify signatures
        _verifySignatures(pawnData, userSignature, backendSignature);
        
        // Check NFT ownership and approval
        if (IERC721(nftContractAddress).ownerOf(pawnData.tokenId) != msg.sender) {
            revert NotTokenOwner();
        }
        
        if (!_isApprovedOrOwner(msg.sender, pawnData.tokenId)) {
            revert ContractNotApproved();
        }
        
        // Check if NFT is already pawned
        if (pawnedNFTs[pawnData.tokenId].active) {
            revert NFTAlreadyPawned();
        }
        
        // Calculate fees
        uint256 fees = (pawnData.bellsAmount * platformFeeRate) / 10000;
        uint256 netAmount = pawnData.bellsAmount - fees;
        
        // Increment nonce
        nonces[msg.sender]++;
        
        // Transfer NFT to contract
        IERC721(nftContractAddress).transferFrom(msg.sender, address(this), pawnData.tokenId);
        
        // Create pawn record
        uint256 expiryTime = block.timestamp + MAX_PAWN_DURATION;
        pawnedNFTs[pawnData.tokenId] = PawnInfo({
            owner: msg.sender,
            bellsAmount: pawnData.bellsAmount,
            pawnTime: block.timestamp,
            expiryTime: expiryTime,
            active: true,
            feesPaid: fees
        });
        
        // Track user's pawned tokens
        userPawnedTokens[msg.sender].push(pawnData.tokenId);
        
        // Update collected fees
        collectedFees += fees;
        
        // Mint tokens to user
        VTest(coinContractAddress).mint(msg.sender, netAmount);
        
        emit NFTPawned(msg.sender, pawnData.tokenId, pawnData.bellsAmount, fees, expiryTime);
    }

    /**
     * @notice Redeem a pawned NFT by paying back the loan
     * @param _tokenId The token ID to redeem
     */
    function redeemNFT(uint256 _tokenId) external nonReentrant whenNotPaused pawnExists(_tokenId) {
        PawnInfo storage pawn = pawnedNFTs[_tokenId];
        
        if (pawn.owner != msg.sender) revert NotTokenOwner();
        if (block.timestamp > pawn.expiryTime) revert PawnExpired();
        
        // Burn tokens from user
        VTest(coinContractAddress).burnFrom(msg.sender, pawn.bellsAmount);
        
        // Clear pawn data
        _clearPawnData(_tokenId);
        
        // Transfer NFT back to owner
        IERC721(nftContractAddress).transferFrom(address(this), msg.sender, _tokenId);
        
        emit NFTRedeemed(msg.sender, _tokenId, pawn.bellsAmount);
    }

    /**
     * @notice Liquidate expired pawns (callable by operators)
     * @param _tokenId The token ID to liquidate
     */
    function liquidateExpiredPawn(uint256 _tokenId) external onlyRole(OPERATOR_ROLE) pawnExists(_tokenId) {
        PawnInfo storage pawn = pawnedNFTs[_tokenId];
        
        if (block.timestamp <= pawn.expiryTime) revert PawnNotExpired();
        
        address originalOwner = pawn.owner;
        uint256 bellsAmount = pawn.bellsAmount;
        
        // Clear pawn data
        _clearPawnData(_tokenId);
        
        // NFT remains in contract (could be transferred to treasury or auctioned)
        
        emit NFTLiquidated(originalOwner, _tokenId, bellsAmount);
    }

    /**
     * @notice Emergency recovery function for stuck NFTs
     * @param _tokenId The token ID to recover
     * @param _to The address to send the NFT to
     */
    function emergencyRecoverNFT(uint256 _tokenId, address _to) 
        external 
        onlyRole(EMERGENCY_ROLE) 
    {
        if (_to == address(0)) revert InvalidAddress();
        
        // Clear pawn data if exists
        if (pawnedNFTs[_tokenId].active) {
            _clearPawnData(_tokenId);
        }
        
        IERC721(nftContractAddress).transferFrom(address(this), _to, _tokenId);
        
        emit EmergencyWithdrawal(_tokenId, _to);
    }

    // Administrative functions
    function updateNFTContract(address _newContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newContract == address(0)) revert InvalidAddress();
        address oldContract = nftContractAddress;
        nftContractAddress = _newContract;
        emit ContractAddressUpdated("NFT", oldContract, _newContract);
    }

    function updateCoinContract(address _newContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newContract == address(0)) revert InvalidAddress();
        address oldContract = coinContractAddress;
        coinContractAddress = _newContract;
        emit ContractAddressUpdated("Coin", oldContract, _newContract);
    }

    function updateFeeRate(uint256 _newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newRate > MAX_FEE_RATE) revert InvalidFeeRate();
        uint256 oldRate = platformFeeRate;
        platformFeeRate = _newRate;
        emit FeeRateUpdated(oldRate, _newRate);
    }

    function updateMaxPawnAmount(uint256 _newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPawnAmount = _newMax;
    }

    function updateFeeCollector(address _newCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newCollector == address(0)) revert InvalidAddress();
        feeCollector = _newCollector;
    }

    function withdrawFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = collectedFees;
        collectedFees = 0;
        VTest(coinContractAddress).mint(feeCollector, amount);
        emit FeesWithdrawn(feeCollector, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // View functions
    function getUserPawnedTokens(address _user) external view returns (uint256[] memory) {
        return userPawnedTokens[_user];
    }

    function isPawnExpired(uint256 _tokenId) external view returns (bool) {
        if (!pawnedNFTs[_tokenId].active) return false;
        return block.timestamp > pawnedNFTs[_tokenId].expiryTime;
    }

    function calculateFees(uint256 _amount) external view returns (uint256) {
        return (_amount * platformFeeRate) / 10000;
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // Internal functions
    function _validatePawnData(PawnSignature calldata pawnData) internal view {
        if (pawnData.owner != msg.sender) revert NotTokenOwner();
        if (pawnData.bellsAmount < MIN_PAWN_AMOUNT) revert InsufficientAmount();
        if (pawnData.bellsAmount > maxPawnAmount) revert ExceedsMaxAmount();
        if (pawnData.nonce != nonces[msg.sender]) revert InvalidSignature();
        if (block.timestamp > pawnData.deadline) revert SignatureExpired();
    }

    function _verifySignatures(
        PawnSignature calldata pawnData,
        bytes calldata userSignature,
        bytes calldata backendSignature
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(
            PAWN_TYPEHASH,
            pawnData.tokenId,
            pawnData.bellsAmount,
            pawnData.owner,
            pawnData.nonce,
            pawnData.deadline
        ));
        
        bytes32 hash = _hashTypedDataV4(structHash);
        
        // Verify user signature
        if (hash.recover(userSignature) != msg.sender) {
            revert InvalidSignature();
        }
        
        // Verify backend signature
        if (!hasRole(BACKEND_ROLE, hash.recover(backendSignature))) {
            revert InvalidSignature();
        }
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        IERC721 nft = IERC721(nftContractAddress);
        return (
            nft.getApproved(tokenId) == spender ||
            nft.isApprovedForAll(nft.ownerOf(tokenId), spender)
        );
    }

    function _clearPawnData(uint256 _tokenId) internal {
        address owner = pawnedNFTs[_tokenId].owner;
        
        // Remove from user's pawned tokens array
        uint256[] storage userTokens = userPawnedTokens[owner];
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == _tokenId) {
                userTokens[i] = userTokens[userTokens.length - 1];
                userTokens.pop();
                break;
            }
        }
        
        // Clear pawn info
        delete pawnedNFTs[_tokenId];
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}
