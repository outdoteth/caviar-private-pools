# Caviar Private Pools

A private pool is a an NFT AMM controlled by a single owner. Each private pool is highly customizable with concentrated liquidity, custom fee rates, stolen NFT filtering, custom NFT weightings, royalty support, and flash loans. Liquidity providers deposit NFTs and ETH into these pools to enable trading. Docs are available [here](https://docs.caviar.sh/technical-reference/custom-pools). And a demo is available on [beta.goerli.caviar.sh](https://beta.goerli.caviar.sh/).

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

| Contract                | LOC | Description                                         | Libraries                                                     |
| ----------------------- | --- | --------------------------------------------------- | ------------------------------------------------------------- |
| EthRouter.sol           | 177 | Routes trades to various pools                      | `solmate` `openzeppelin` `royalty-registry-solidity` `caviar` |
| Factory.sol             | 83  | Creates new pools and also accrues protocol fees    | `solady` `solmate`                                            |
| PrivatePool.sol         | 375 | Core AMM logic for each newly deployed private pool | `solady` `solmate` `openzeppelin` `royalty-registry-solidity` |
| PrivatePoolMetadata.sol | 90  | Generates NFT metadata and svgs for each pool       | `solmate` `openzeppelin`                                      |

## External imports

- **solmate/tokens/ERC721.sol**
  - [src/EthRouter.sol](./src/EthRouter.sol)
  - [src/Factory.sol](./src/Factory.sol)
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **solmate/utils/SafeTransferLib.sol**
  - [src/EthRouter.sol](./src/EthRouter.sol)
  - [src/Factory.sol](./src/Factory.sol)
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **solmate/tokens/ERC20.sol**
  - [src/Factory.sol](./src/Factory.sol)
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **solmate/auth/Owned.sol**
  - [src/Factory.sol](./src/Factory.sol)
- **solmate/utils/FixedPointMathLib.sol**
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **caviar/Pair.sol**
  - [src/EthRouter.sol](./src/EthRouter.sol)
- **royalty-registry-solidity/IRoyaltyRegistry.sol**
  - [src/EthRouter.sol](./src/EthRouter.sol)
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **solady/utils/LibClone.sol**
  - [src/Factory.sol](./src/Factory.sol)
- **solady/utils/MerkleProofLib.sol**
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **openzeppelin/interfaces/IERC2981.sol**
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **openzeppelin/interfaces/IERC3156FlashLender.sol**
  - [src/PrivatePool.sol](./src/PrivatePool.sol)
- **openzeppelin/interfaces/IERC2981.sol**
  - [src/EthRouter.sol](./src/EthRouter.sol)
