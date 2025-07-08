This smart contract was made as part of the Televault project, a decentralized application made to let users deposit their vaulted bellscoin NFT to this smart contract and have it give the users eth based on the vaulted amount. This is done through a multi signature authentication system, the user sends their digital signature to the contract along with the NFT, a backend API will then confirm the ownership and amount of the NFT and sends its own signature to the contract once confirmation is complete. When the two signatures are received by the contract then the trade happens. 

This repository contains the smart contract and a simple sample dApp to test it.

The contract was deployed to the Arbitrum Sepolia testnet for testing.


Features:

    1. Escrows NFTs.
    2. Trades bells to eth and vice versa.
    3. Multisig authentication.
    4. Multicontract setup for increased security and gas efficiency.
    5. Time limited authentication, returns NFT if authentication fails.

To Deploy Contracts:

    1. npx hardhat compile
    2. npx hardhat run scripts/deploy_vtest.ts --network arbitrumSepolia
    3. copy output address.
    4. npx hardhat verify [copied address] --network arbitrumSepolia
    5. paste [copied address] to coinContractAddress in Contracts/escrow.sol
    6. npx hardhat run scripts/deploy_escrow.ts --network arbitrumSepolia
    7. copy output address
    8. npx hardhat verify [copied address] --network arbitrumSepolia
    9. Transfer ownership of coin contract to escrow contract

UPDATE: Performed security audit and fixed vulnerabilities for learning purposes.
