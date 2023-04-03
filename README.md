# Caviar Private Pools

A private pool is a an NFT AMM controlled by a single owner. Each private pool is highly customizable with concentrated liquidity, custom fee rates, stolen NFT filtering, custom NFT weightings, royalty support, and flash loans. Liquidity providers deposit NFTs and ETH into these pools to enable trading. Docs are available [here](https://docs.caviar.sh/technical-reference/custom-pools).

## Getting started

```
yarn
forge install
forge test --gas-report --ffi
```

## System overview

- The [Factory](./src/Factory.sol) contract allows users to create and initialize new custom pools that are minimal proxies which point to a reference implementation. It is responsible for issuing NFTs that represent ownership of each custom pool. All protocol fees accrue to the factory contract and can be withdrawn by the protocol admin. Initially the protocol fee rate will be set to be 0% however it may be increased in the future, with advanced notice.

- The [PrivatePool](./src/PrivatePool.sol) contract contains all of the core logic for custom pools. It allows users to set concentrated liquidity, custom fee rates, NFT weightings, change/flashloan fee rates, royalty fee support, and stolen NFT filtering. Traders can buy, sell, and change NFTs for other NFTs within the pool.

- The [EthRouter](./src/EthRouter.sol) contract is responsible for taking in a sequence of actions and executing them against the various pools. This is useful if a user wants to buy N amount of NFTs that belong to Y different pools. For example, Bob wants to buy token #1, #2, and #3. Token #1 belongs to pool A. Tokens #2, and #3 belong to pool B. Bob can submit an array of buys to the EthRouter and it will execute a buy from both pool A and pool B in one transaction. The EthRouter also interfaces with caviar public pools, which can be found [here](https://github.com/outdoteth/caviar).

- The [PrivatePoolMetadata](./src/PrivatePoolMetadata.sol) contract is responsible for generating an on-chain svg and metadata representation of the NFT that represents ownership of a custom pool. This is used to display the NFT across various marketplaces and wallets.

## Contracts overview

| Contract                | LOC |
| ----------------------- | --- |
| EthRouter.sol           | 177 |
| Factory.sol             | 83  |
| PrivatePool.sol         | 375 |
| PrivatePoolMetadata.sol | 90  |
