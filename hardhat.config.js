require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config()



const { setGlobalDispatcher, ProxyAgent } = require('undici')
const proxyAgent = new ProxyAgent('http://127.0.0.1:1087')
setGlobalDispatcher(proxyAgent)


const goerliAccount = process.env.goerliAccount
const goerliUrl = process.env.goerliUrl

const mainnetAccount = process.env.mainnetAccount
const mainnetUrl = process.env.mainnetUrl

const ethscanKey = process.env.ethscanKey


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: { yul: false },
      },
    },
  },

  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },

  // networks: {
  //   goerli: {
  //     url: goerliUrl,
  //     accounts: [
  //       goerliAccount
  //     ],
  //   },
  //   mainnet: {
  //     url: mainnetUrl,
  //     accounts: [
  //       mainnetAccount
  //     ],
  //   }
  // },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      chainId: 1,
      forking: {
        url: `https://eth-mainnet.g.alchemy.com/v2/kNPJaYqMx7BA9TcDDJQ8pS5WcLqXGiG7`,
        blockNumber: 16695137,
      },
    },
  },
  etherscan: {
    apiKey: ethscanKey
  },
};
