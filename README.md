# Project Title

xWIN Finance v2 Smart Contracts

## Description

xWin Finance V2 is an enhanced version of DEFI platform on the Binance Smart Chain and Ethereum network that uses advanced algorithms and optimization techniques to help you create and manage your portfolio based on your risk tolerance and investment goals. xWin Robo Advisor, a new feature in xWIN Finance V2, you can optimize your portfolio through different optimization approaches. You can have various native tokens such as BTC or ETH or integrating xWin strategies tokens into your portfolio.

But that's not all - xWin Finance V2 also offers the option to deploy your own private vaults, where your funds are secured in a smart contract and can only be accessed by you. And if you're feeling ambitious, you can even become a fund manager by opening your vault to the public, earning management and performance fees in the process.

## Security & Certik Audit Report

https://skynet.certik.com/projects/xwinfinance

## Support Network
* BNB Network - LIVE
* Polygon Network - LIVE
* Arbitrum Network - LIVE
* ETHEREUM Network - TO BE SUPPORTED in Q4 2024

## Main Smart Contracts

Name  | Address
------------- | -------------
xWIN Swap  | 0x9Ce3fCffaeB4B7Fbdf39E9313F845d977393D8d1
xWIN TWAP  | 0x7A8aa080EAdA0b670fb719D7E53f87898a1299Ac
xWIN PriceMaster  | 0xB1233713FeA0984fff84c7456d2cCed43e5e48E2
xWIN EventEmitter  | 0xc4c0171A31b6CEd6daA4342343425F2eeA703cc6
xWIN FundV2Factory  | 0x9ab3c504De0fDa0087D378123bDC318AADbC60a0
xWIN Locked Auto Compound  | 0xa4AE0DCC89Af9855946C0b2ad4A10FF27125a9Fc
xWIN MasterChef  | 0xD09774e3d5Dc02fa969896c53D3Cbb5bC8900A60
xWIN BuddyChef  | 0x4B87a60fC5a94e5ac886867977e29c9711C2E903



## xWIN Strategies Smart Contracts

Symbol  | Name  | Address
------------- | ------------- | -------------
xSCA|   (BTC) Stable USDT Alpha | 0x0a652784DF3f8Abde85dAEeee77D1EA97f5c5B24
xDCA|   (BTC) Dollar Cost Average | 0x482ae949E4a70953fCa090717b68359b73b8602a
xWinBBMA| (BTC) Band Bollinger Moving Average | 0x5EFaaBc34a3ba66f1fD02F056AC457AeBaF57D55
xWinIRT| (BTC) Interest Rate Indicator | 0x5A8a66DF53DF88844c60829967b88d00eD208E08
xCAKE-V| CAKE Staking Venus | 0x1d2430bBfe86432E36A7C7286E99f78546F23De9
xETH-V| ETH Staking Venus | 0x0C34Aa4e36983aB6ec11bC557A3B8cF79A7a9Ae7
xUSDC-V| USDC Staking Venus | 0xcBca44d60c5A2b3c56ACfB51aFC66Ea04b8a2742
xBUSD-V| BUSD Staking Venus | 0xf4979C043df6f7d5dA929DeAB11b220A82886395
xBTC-V| BTC Staking Venus | 0x7A0dEc70473602Cd0EF3Dc3d909b6Dc3FA42116C
xUSDT-V| USDT Staking Venus | 0x8B7fcACB99124F009c8470FDa6f5fcF60277BDB2
xADA-V| ADA Staking Venus | 0x605926F795FD9B4c3A8B1A2db33cBE01c66bA83f
xBTC-O| BTC Staking OlaFinance | 0x69764856e82180150f5366be610E40c2f812d7D6
xUSDT-O| USDT Staking OlaFinance | 0xCEbd365e4BFd8589Fd6BDe21898DB35a8095f956
    

## xWIN Public Allocation Vaults Smart Contracts

Symbol  | Name  | Address
------------- | ------------- | -------------
fDEFI|  xWIN DEFI Index | 0x61d5722290F8755b2f31D260064658D6Ad837F37
fMIV|  Major Index Vault | 0x0A0817454710102F2bcB2215D616cBe3aFf495e5
fxDollar|  Dollar Zanmai | 0xFa4d4B4243dDA1F5f4d09269f61D57d02470635C
fBTCETH|  BTC-ETH-50-50 | 0x284b4aDD0C9669f635EA64418C216821c45D0B48
fvUSDT|  USDT Venus / Ola Staking | 0xE949d266E8740470a15DFB1F40A795b5a2b63f02
fCombo|  xWIN Combo | 0x4d4F948C8E9Ec3d1cE1B80d598f57F8c75c64e4a
fTACombo|  xWIN TA Combo | 0xaaFF5eFe1376474a520FFe9129d8Aa8d7422AAbe

### Dapps

* https://app.xwin.finance
* https://xwin.finance


### Hardhat Environment

This project uses the hardhat development environment. To run the project first, run the following command:

```bash
npm install
```

Then create a secrets.json file with the following properties:

```json
{
    "privateKey": "<your private key>",
    "bscNode": "<your bsc archive node>",
    "ethereumNode": "<your eth archive node>",
    "arbitrumNode": "<your arb archive node>",
    "polygonNode" : "<your polygon archive node>"
}
```

The private key is for live networks, and the nodes are for running local forks of the respective blockchain. An archive node is required to run the forking feature. All the tests are done using the bscNode.

To compile the contracts, run the following command:

```bash
npx hardhat compile
```

To run the tests, run the following command:

```bash
npx hardhat test
```

To modify the local fork chainId or blocknumber, go to [fork.configs.js](fork.configs.js).

## Authors

xWIN Technology 
3-5-3, Tower 3, UOA Business Park, No. 1, Jalan Pengaturcara U1/51A, Seksyen 1, Shah Alam, Selangor 40150, MY

Email: admin@xwin.com.my

[@Twitter](https://twitter.com/xwinfinance)

[@Telegram](https://www.t.me/xwinfinance)


## License

This project is licensed under the MIT License


