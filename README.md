To Deploy Contracts

1. npx hardhat compile
2. npx hardhat run scripts/deploy_vtest.ts --network arbitrumSepolia
3. copy output address
4. npx hardhat verify [copied address] --network arbitrumSepolia
5. paste [copied address] to coinContractAddress in Contracts/escrow.sol
6. npx hardhat run scripts/deploy_escrow.ts --network arbitrumSepolia
7. copy output address
8. npx hardhat verify [copied address] --network arbitrumSepolia
9. Transfer ownership of coin contract to escrow contract