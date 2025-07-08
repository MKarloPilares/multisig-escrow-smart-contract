import { ethers } from "hardhat";

async function main() {
  console.log("Deploying MultiSigNFTEscrow contract...");
  
  const contract = await ethers.deployContract("MultiSigNFTEscrow");
  await contract.waitForDeployment();
  
  console.log(`MultiSigNFTEscrow deployed to: ${contract.target}`);
  
  // Log the contract addresses that are hardcoded in the constructor
  console.log("Contract configuration:");
  console.log(`NFT Contract Address: ${await contract.nftContractAddress()}`);
  console.log(`Coin Contract Address: ${await contract.coinContractAddress()}`);
  console.log(`Backend Address: ${await contract.backEndAddress()}`);
  console.log(`Contract Owner: ${await contract.owner()}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});