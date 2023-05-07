# `DualTokenVoting` Aragon OSx Plugin

*Submitted for ([DAO Global Hackathon](https://daoglobalhackathon.hackerearth.com/)) [Aragon] Best Decision-Making Plugin*

An Aragon OSx plugin for using a member/citizenship token alongside a voting power token.

## Getting Started
This plugin is currently in beta on the Polygon Mumbai testnet. Feel free to interact with the plugin via the live testnet setup repo or by pulling this project. 

To test this plugin quickly we recommend pulling the project, installing dependencies and testing on a local hardhat fork of Mumbai. 

### Pre Requisites

Before being able to run any command, you need to create a `.env` file and set a private key as an environment variable. To test the contracts against the current Aragon OSx contracts on any of the supported networks, you must also set an Infura API key. If you don't already have an Infura API key, you can sign up for one at [Infura](https://app.infura.io/login).

Copy and enter the following environment variables in your `.env` file
```
PRIVATE_KEY=
INFURA_API_KEY=
HARDHAT_FORK_NETWORK="polygonMumbai" #  ["arbitrumOne", "arbitrumGoerli", "mainnet", "goerli", "polygon", "polygonMumbai"]
```

Then, proceed with installing dependencies:

```sh
$ yarn install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

### TypeChain

Generate TypeChain bindings:

```sh
$ yarn typechain
```

### Test

Run the tests with Hardhat:

```sh
$ yarn test
```

Currently the tests are restricted using the `.only()` flag to those that are relevant specifically to the member token implementation.

## Notes
Currently for external/existing member tokens, there is only support for ERC721. We intend to expand this to include ERC1155 and potentially others in the near future.

## Why did we build this?
At [Unbound Labs](https://www.unboundlabs.io) we believe that DAOs are critical for the future of innovation. We believe that by using a DAO structure to share ownership between users and builders, organizations can grow faster, build better products/services, reduce churn, and operate more equitably. Unbound Labs is proving this vision by building decentralized marketplaces in specialized markets such as [DiVerity](https://www.diverity.com).

### The Problem
To create a system for community-ownership we need provide a mechanism for community members to earn ownership (tokens) that provides governance rights and potentially represents some upside through public listing. Unfortunately, while publicly listing a token can provide members with more liquidity and upside, it also opens the community up for the "Elon Musk Takeover". While voting restrictions via thresholds and caps can help prevent these issues we believe that many communities could benefit from a system of tokenized membership/citizenship that does not interfere with the benefits of the governance token. 

### The Solution
We have created a plugin for the Aragon OSx framework that allows a DAO to create a NTT (Non-Transferable Token) that represents the member's citizenship in the DAO. This NTT operates alongside the DAOs governance token (referred to in the plugin as "Voting Power Token"). With the DualTokenVoting plugin DAOs have both a membership token that determines a member's right to vote and a voting power token that determines the member's voting power. 

We believe that this system can benefit communities that would like to publicly list their token to create improved liquidity and potential upside while not affecting the community's direction. This will also benefit speculative investors by increasing the number of communities that can publicly list their governance tokens.

While by default this plugin will create a NTT to represent membership, NFT communities can also leverage this plugin to create a DAO with their existing NFTs representing membership and a separate governance token representing each member's voting power. 

## Contributions
Ketul "Jay" Patel -- Co-Founder @ Unbound Labs [LinkedIn](https://www.linkedin.com/in/ketul-jay-patel-238a5453/)

## License

This project is licensed under AGPL-3.0-or-later.
