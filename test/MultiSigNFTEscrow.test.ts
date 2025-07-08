import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { MultiSigNFTEscrow, VTest } from "../typechain-types";

describe("MultiSigNFTEscrow Security & Logic Tests", function () {
  let escrow: MultiSigNFTEscrow;
  let nftContract: any;
  let coinContract: VTest;
  let owner: Signer;
  let user: Signer;
  let backend: Signer;
  let attacker: Signer;
  
  const TOKEN_ID = 1;
  const BELLS_AMOUNT = ethers.parseEther("100");

  beforeEach(async function () {
    [owner, user, backend, attacker] = await ethers.getSigners();
    
    // Deploy mock NFT contract
    const MockNFT = await ethers.getContractFactory("MockNFT");
    nftContract = await MockNFT.deploy();
    
    // Deploy VTest coin contract
    const VTestFactory = await ethers.getContractFactory("VTest");
    coinContract = await VTestFactory.deploy();
    
    // Deploy escrow contract
    const EscrowFactory = await ethers.getContractFactory("MultiSigNFTEscrow");
    escrow = await EscrowFactory.deploy();
    
    // Update contract addresses
    await escrow.updateAddresses(
      await nftContract.getAddress(),
      await coinContract.getAddress(),
      await backend.getAddress()
    );
    
    // Mint NFT to user and approve escrow
    await nftContract.mint(await user.getAddress(), TOKEN_ID);
    await nftContract.connect(user).approve(await escrow.getAddress(), TOKEN_ID);
  });

  describe("Security Tests", function () {
    it("Should prevent reentrancy attacks", async function () {
      // Test reentrancy protection
      const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
      const attackContract = await ReentrancyAttacker.deploy(await escrow.getAddress());
      
      await expect(
        attackContract.attack(TOKEN_ID, BELLS_AMOUNT)
      ).to.be.revertedWith("ReentrancyGuard: reentrant call");
    });

    it("Should prevent signature replay attacks", async function () {
      const userAddress = await user.getAddress();
      const nonce = await escrow.nonces(userAddress);
      
      // Create valid signatures
      const messageHash = ethers.solidityPackedKeccak256(
        ["uint256", "uint256", "address", "uint256"],
        [TOKEN_ID, BELLS_AMOUNT, userAddress, nonce]
      );
      
      const custSignature = await user.signMessage(ethers.getBytes(messageHash));
      const apiSignature = await backend.signMessage(ethers.getBytes(messageHash));
      
      const custSig = ethers.Signature.from(custSignature);
      const apiSig = ethers.Signature.from(apiSignature);
      
      // First transaction should succeed
      await escrow.connect(user).pawn(
        TOKEN_ID, BELLS_AMOUNT,
        messageHash, messageHash,
        custSig.v, custSig.r, custSig.s,
        apiSig.v, apiSig.r, apiSig.s
      );
      
      // Replay attack should fail
      await expect(
        escrow.connect(user).pawn(
          TOKEN_ID, BELLS_AMOUNT,
          messageHash, messageHash,
          custSig.v, custSig.r, custSig.s,
          apiSig.v, apiSig.r, apiSig.s
        )
      ).to.be.revertedWith("Invalid customer message hash");
    });

    it("Should reject invalid signatures", async function () {
      const userAddress = await user.getAddress();
      const nonce = await escrow.nonces(userAddress);
      
      const messageHash = ethers.solidityPackedKeccak256(
        ["uint256", "uint256", "address", "uint256"],
        [TOKEN_ID, BELLS_AMOUNT, userAddress, nonce]
      );
      
      // Invalid signature from attacker
      const invalidSignature = await attacker.signMessage(ethers.getBytes(messageHash));
      const validSignature = await backend.signMessage(ethers.getBytes(messageHash));
      
      const invalidSig = ethers.Signature.from(invalidSignature);
      const validSig = ethers.Signature.from(validSignature);
      
      await expect(
        escrow.connect(user).pawn(
          TOKEN_ID, BELLS_AMOUNT,
          messageHash, messageHash,
          invalidSig.v, invalidSig.r, invalidSig.s,
          validSig.v, validSig.r, validSig.s
        )
      ).to.be.revertedWith("Invalid customer signature");
    });

    it("Should prevent unauthorized access to giveBackNft", async function () {
      // This test reveals the security flaw
      await expect(
        escrow.connect(attacker).giveBackNft(TOKEN_ID)
      ).to.be.revertedWith("NFT not in contract");
    });
  });

  describe("Logic Tests", function () {
    it("Should correctly execute pawn process", async function () {
      const userAddress = await user.getAddress();
      const nonce = await escrow.nonces(userAddress);
      
      const messageHash = ethers.solidityPackedKeccak256(
        ["uint256", "uint256", "address", "uint256"],
        [TOKEN_ID, BELLS_AMOUNT, userAddress, nonce]
      );
      
      const custSignature = await user.signMessage(ethers.getBytes(messageHash));
      const apiSignature = await backend.signMessage(ethers.getBytes(messageHash));
      
      const custSig = ethers.Signature.from(custSignature);
      const apiSig = ethers.Signature.from(apiSignature);
      
      // Check initial state
      expect(await nftContract.ownerOf(TOKEN_ID)).to.equal(userAddress);
      expect(await coinContract.balanceOf(userAddress)).to.equal(0);
      
      // Execute pawn
      await escrow.connect(user).pawn(
        TOKEN_ID, BELLS_AMOUNT,
        messageHash, messageHash,
        custSig.v, custSig.r, custSig.s,
        apiSig.v, apiSig.r, apiSig.s
      );
      
      // Verify final state
      expect(await nftContract.ownerOf(TOKEN_ID)).to.equal(await escrow.getAddress());
      expect(await coinContract.balanceOf(userAddress)).to.equal(BELLS_AMOUNT);
      expect(await escrow.nonces(userAddress)).to.equal(nonce + 1n);
    });

    it("Should validate input parameters", async function () {
      const userAddress = await user.getAddress();
      
      await expect(
        escrow.connect(user).pawn(0, BELLS_AMOUNT, "0x", "0x", 0, "0x", "0x", 0, "0x", "0x")
      ).to.be.revertedWith("Invalid token ID");
      
      await expect(
        escrow.connect(user).pawn(TOKEN_ID, 0, "0x", "0x", 0, "0x", "0x", 0, "0x", "0x")
      ).to.be.revertedWith("Invalid bells amount");
    });
  });

  describe("Access Control Tests", function () {
    it("Should allow only owner to update addresses", async function () {
      await expect(
        escrow.connect(attacker).updateAddresses(
          await nftContract.getAddress(),
          await coinContract.getAddress(),
          await backend.getAddress()
        )
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow only owner to emergency recover NFTs", async function () {
      await expect(
        escrow.connect(attacker).emergencyRecoverNFT(TOKEN_ID, await attacker.getAddress())
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});
