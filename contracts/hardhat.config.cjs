require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const networks = {
  hardhat: { chainId: 31337 },
  bscTestnet: {
    url: process.env.BSC_TESTNET_RPC_URL || "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
    chainId: 97,
    accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
  },
};
module.exports = { solidity: { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 } } }, networks };
