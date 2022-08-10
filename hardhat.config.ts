import 'dotenv/config' ;
import 'hardhat-deploy';
// Allwos generating docs. much wow
import "solidity-docgen";
import "hardhat-contract-sizer";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";

// require("@nomicfoundation/hardhat-toolbox");

// This adds support for typescript paths mappings
// require("tsconfig-paths/register");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
// task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
//   const accounts = await hre.ethers.getSigners();

//   for (const account of accounts) {
//     console.log(account.address);
//   }
// });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.9",
  settings: {
    optimizer: {
      enabled: true,
      runs: 1000,
    },
  },
  verify: {
    etherscan: {
      apiKey: '<API key>'
    }
  },
  networks: {
    mainnet: {
      url: process.env.MAINNET_ETH_RPC || "",
      accounts: {
        mnemonic: process.env.MAINNET_ETH_MNEMONIC,
      },
      deploy: [ 'deploy/' ],
      verify: {
        etherscan: {
          apiUrl: 'https://etherscan.io/'
        }
      }
    },
    gorli: {
      url: process.env.GORLI_ETH_RPC || "",
      accounts: {
        mnemonic: process.env.GORLI_ETH_MNEMONIC,
      },
      deploy: [ 'deploy-testnet/' ],
      verify: {
        etherscan: {
          apiUrl: 'https://goerli.etherscan.io/'
        }
      }
    },
  },
  docgen: { // create doc site from NATSPEC
    pages: 'files',
    sourcesDir: 'contracts/modules'
  }
};