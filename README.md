# CoinSwap Contracts

This is a prototype implementation of DEX for Ethereum using Solidity. The technique is based on Dr. Wang's paper: 
[Automated Market Makers for Decentralized Finance (DeFi)](https://arxiv.org/pdf/2009.01676.pdf) 

The goals of CoinSwap (based on the constant circle model) is to reduce the slippage cost. The implementation is based on the Uniswap V2 architecture and framework. During our implementation of the CoinSwap protocol, we found out that some of our modules could be used
to reduce the gas cost for Uniswap V2. Our optimized Uniswap V2 was included in the file 
[uniswap-v2-periphery-optimized.zip](https://github.com/coinswapapp/coinswap-smart-contracts/raw/main/uniswap-v2-periphery-optimized.zip). After you unzip the file, you can run the following command to test the gas cost:
- yarn install (or npm install)
- yarn test

You may just copy the gastest.spec.ts file to the original [uniswap-v2-periphery](https://github.com/Uniswap/uniswap-v2-periphery) folder to test the origianl gas cost for Uniswap V2 (note that you may need to increase the initial token number in the shared/fixtures.ts).

The following is a coparison of the gas cost for Original Uniswap V2, Optimized Uniswap V2, Curve Finance, and our Coinswap

 function() | Uniswap V2  | Optimized Uniswap V2 | Curve Finance (balanced) | Curve Finance (imbalanced) | CoinSwap | GAS Saving (over Uniswap V2)
 ------------- | -------------|-------------|-------------|-------------|-------|-----
mine() | 141106  | 132205 | 55798 (Y) | 55798 (Y) | 109759 | 22.2414%
swap() | 89894  | 88101 | || 89343 | 0.6074%
swap() (first transaction each block) | 101910 |99889| | | 96216|5.5107%
addLiquidity | 216512|207163|517639 | 411805 |185368 | 14.3502%
removeLiquidity | 98597|97329|254592| 506064| 67137 | 31.9178%
addLiquidity (ETH/WETH) | 223074|213725|||191953 |13.9178%
full removeLiquidity (ETH/WETH) | 122071 |122061|||98815 | 19.8915%
partial removeLiquidity (ETH/WETH) | 180355|137071|||144235 | 20.0006%

The above comparison shows that CoinSwap has less gas cost than the optimized Uniswap V2.The major application of CoinSwap is for relatively stable digital properties such as stable coins. 

We should note the following comparison from https://hackmd.io/@HaydenAdams/HJ9jLsfTz for other swap gas cost.

The following are the deployed smart contract addresses:

- CoinSwapFactory: 0x12ee90f9b476f1808544c1e8abe1266d95e5e613 (Ethereum mainnet)
- CoinSwapRouter: 0xc6edc0703b7f20dc184f72c0621700a8d872c9b3 (Ethereum mainnet)
- CSWP Governance Token: 0xC882CCD810f0ce07FeaE297260F474FA7F6c7999 (Ethereum mainnet)
- 
- CoinSwapFactory: 0x095122e22f45624c5a3cf3f6a1eda6a0be813aef (BSC mainnet)
- Wrapped BNB: 0x33af73aa6aaea0bd8a237758f14b4c341d7b251b (BSC mainnet)
- CoinSwapRouter: 0x6ca292a38c13718c763110ea159c9ed2b9dd2b88 (BSC mainnet)
- CSWP Governance Token: 0x00ad91fB399eDa6223Dc387e792fdD7a35E16337 (BSC mainnet)
- 
- CoinSwapFactory: 0x2abfc7d35abdb3b1c1b1722db56224c3d781311c (OKchain testnet)
- Wrapped OKT: 0x6d0acfe5cfabb2cf5dd55b85c82db18cd6d1fb57 (OKchain testnet)
- CoinSwapRouter: 0x095122e22f45624c5a3cf3f6a1eda6a0be813aef (OKchain testnet)
- 
- CoinSwapFactory: 0x6834464C558B3EE784703F44903467Cd2558b0f0 (HECO testnet)
- Wrapped HT: 0x2AbFC7D35ABdB3b1C1B1722dB56224C3d781311c (HECO testnet)
- CoinSwapRouter: 0x8aCe3e9aD87Bd171B281d800F9bbB78d73ae9cc7 (HECO testnet)

The UI could be accessed at:

1. https://yonggewang.github.io/ethcoinswap/ (or http://quantumca.org/ethcoinswap ) (Ethereum mainnet)
2. https://yonggewang.github.io/bsccoinswap/ (or http://quantumca.org/bsccoinswap ) (BSC mainnet)
3. https://yonggewang.github.io/okcoinswap/ (or http://quantumca.org/okcoinswap ) (OK testnet)
4. https://yonggewang.github.io/hecocoinswap/ (or http://quantumca.org/hecocoinswap ) (HECO testnet)
