import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";
import "solidity-coverage";
import "hardhat-gas-reporter";

const ARBITRUM_SEPOLIA_URL = process.env.ARBITRUM_SEPOLIA_URL ?? "";
const PRIVATE_KEY = process.env.PRIVATE_KEY ?? "";
const ETHER_API_KEY = process.env.ETHER_API_KEY ?? "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  networks: {
    sepolia: {
      url: ARBITRUM_SEPOLIA_URL,
      accounts: [PRIVATE_KEY],
    },
    arbitrumSepolia: {
      url: ARBITRUM_SEPOLIA_URL,
      accounts: [PRIVATE_KEY],
      chainId: 421614,
    },
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: ETHER_API_KEY,
    customChains: [
      {
        network: "arbsep",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io/",
        },
      },
    ],
  },
};

export default config;