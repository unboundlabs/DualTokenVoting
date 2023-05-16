import {NetworkNameMapping} from './utils/helpers';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-etherscan';
import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import {config as dotenvConfig} from 'dotenv';
import {BigNumber} from 'ethers';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import {extendEnvironment, HardhatUserConfig} from 'hardhat/config';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import type {NetworkUserConfig} from 'hardhat/types';
import {resolve} from 'path';
import 'solidity-coverage';


const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || './.env';
dotenvConfig({path: resolve(__dirname, dotenvConfigPath)});

// Using a timestamp string to avoid naming conflicts for test deployments
// Change this for live deployment
process.env.PLUGIN_UID = Date.now().toString()

if (!process.env.INFURA_API_KEY) {
  throw new Error('INFURA_API_KEY in .env not set');
}

const apiUrls: NetworkNameMapping = {
  arbitrumOne: 'https://arbitrumOne.infura.io/v3/',
  arbitrumGoerli: 'https://arbitrumGoerli.infura.io/v3/',
  mainnet: 'https://mainnet.infura.io/v3/',
  goerli: 'https://goerli.infura.io/v3/',
  polygon: 'https://polygon-mainnet.infura.io/v3/',
  polygonMumbai: 'https://polygon-mumbai.infura.io/v3/',
};

const networks: {[index: string]: NetworkUserConfig} = {
  hardhat: {
    chainId: 31337,
    forking: {
      url: `${
        apiUrls[
          process.env.HARDHAT_FORK_NETWORK
            ? process.env.HARDHAT_FORK_NETWORK
            : 'mainnet'
        ]
      }${process.env.INFURA_API_KEY}`,
    },
  },
  mainnet: {
    chainId: 1,
    url: `${apiUrls.mainnet}${process.env.INFURA_API_KEY}`,
  },
  goerli: {
    chainId: 5,
    url: `${apiUrls.goerli}${process.env.INFURA_API_KEY}`,
  },
  polygon: {
    chainId: 137,
    url: `${apiUrls.polygon}${process.env.INFURA_API_KEY}`,
  },
  polygonMumbai: {
    chainId: 80001,
    url: `${apiUrls.polygonMumbai}${process.env.INFURA_API_KEY}`,
  },
};

// Uses hardhats private key if none is set. DON'T USE THIS ACCOUNT FOR DEPLOYMENTS
const accounts = process.env.PRIVATE_KEY
  ? process.env.PRIVATE_KEY.split(',')
  : ['0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'];

for (const network in networks) {
  // special treatement for hardhat
  if (network.startsWith('hardhat')) {
    // add 20 more recognizable standard hardhat accounts for testing
    accounts.push(...[
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
      '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
      '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
      '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a',
      '0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba',
      '0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e',
      '0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356',
      '0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97',
      '0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6',
      '0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897',
      '0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82',
      '0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1',
      '0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd',
      '0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa',
      '0x8166f546bab6da521a8369cab06c5d2b9e46670292d85c875ee9ec20e84ffb61',
      '0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0',
      '0x689af8efa8c651a91ad287602527f3af2fe9f6501a7ac4b061667b5a93e037fd',
      '0xde9be858da4a475276426320d5e9262ecfc3ba460bfac56360bfa6c4c28b4ee0',
      '0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e',
    ])
    networks[network].accounts = accounts.map(account => ({
      privateKey: account,
      balance: BigNumber.from(10).pow(20).toString(), // Set balance to 100 ETH
    }));

    continue;
  }
  networks[network].accounts = accounts;
}

// Extend HardhatRuntimeEnvironment
extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.aragonToVerifyContracts = [];
});

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY || '',
      arbitrumGoerli: process.env.ARBISCAN_API_KEY || '',
      mainnet: process.env.ETHERSCAN_API_KEY || '',
      goerli: process.env.ETHERSCAN_API_KEY || '',
      polygon: process.env.POLYGONSCAN_API_KEY || '',
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || '',
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  gasReporter: {
    currency: 'USD',
    enabled: process.env.REPORT_GAS === 'true' ? true : false,
    excludeContracts: [],
    src: './contracts',
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  networks,
  paths: {
    artifacts: './artifacts',
    cache: './cache',
    sources: './contracts',
    tests: './test',
    deploy: './deploy',
  },

  solidity: {
    version: '0.8.17',
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/hardhat-template/issues/31
        bytecodeHash: 'none',
      },
      // Disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};

export default config;
