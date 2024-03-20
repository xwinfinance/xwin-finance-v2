require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-toolbox");

const { privateKey, bscNode, ethereumNode, arbitrumNode, polygonNode} = require('./secrets.json');

// Forking configs: modify the values to determine the forking chain and block number
const forkChain = 56;
const forkBlockNumber = 1234567;







module.exports = {
  networks: {
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      forking: {
        url: bscNode,
        blockNumber: 35227815,
      }
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      gasPrice: 10000000000,
      accounts: [privateKey],
    },
    mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      gasPrice: 3000000000, // 3 gwei
      accounts: [privateKey],
    },
    arbmainnet: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      gasPrice: 100000000, // 0.1 gwei
      accounts: [privateKey],
    },
    polygonmainnet: {
      url: "https://polygon-mainnet.g.alchemy.com/v2/jydIA5GrZHPUZRsNAxE3HFgMtIEny2os",
      chainId: 137,
      gasPrice: 60000000000, // 50 gwei
      accounts: [privateKey],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  gasReporter: {
    enabled: false,
    currency: "ETH",
    gasPrice: 0.1,
  },
  // etherscan: {
  //   apiKey: {
  //     bsc: ''
  //   }
  // }
};
