const {
  deployxWinSwapV3,
  deployTWAP,
  deployxWinEmitEvent,
  deployxWinDCA,
  deployxWinTokenAlpha,
  deployxWinPriceMaster,
  deployxWinSingleAsset,
  swapBNB,
  deployFundV2Factory,
  // deployxWinDefi,
  // deployxWinMasterChef,
  // deployLockStaking,
} = require("./xWinTestHelpers.js");
const { arb, hardhatNode } = require("./arbMainnetAddresses.js");
const { ethers } = require("hardhat");

async function xWinFixture() {
  // Contracts are deployed using the first signer/account by default
  const [owner, ...accounts] = await ethers.getSigners();

  // deploy core helper contracts
  const xWinSwapV3 = await deployxWinSwapV3(owner);
  const xWinTWAP = await deployTWAP();
  const xWinPriceMaster = await deployxWinPriceMaster(
    owner,
    await xWinSwapV3.getAddress(),
    await xWinTWAP.getAddress()
  );
  await xWinSwapV3.setPriceMaster(await xWinPriceMaster.getAddress());

  const xWinEmitEvent = await deployxWinEmitEvent();

  // // deploy farming/staking contracts
  // const xWinDefi = await deployxWinDefi(owner);
  // const xWinMasterChef = await deployxWinMasterChef(xWinDefi, xWinPriceMaster);
  // const xWinLockStaking = await deployLockStaking(owner, xWinMasterChef);

  // deploy factory contract
  const xWinFundV2Factory = await deployFundV2Factory(
    xWinSwapV3,
    xWinEmitEvent,
    xWinPriceMaster,
    arb.address0
  );

  // ======== core setup completed =============

  // deploy funds and strategy contracts
  const xUSDC = await deployxWinSingleAsset(
    "xUSDC Derivative",
    "xUSDC",
    arb.USDC,
    await xWinSwapV3.getAddress(),
    await xWinPriceMaster.getAddress(),
    arb.USDC,
    arb.aUSDC,
    arb.aavePool,
    arb.aavePoolDataProvider,
    xWinEmitEvent
  );
  

  const xUSDT = await deployxWinSingleAsset(
    "xUSDT Derivative",
    "xUSDT",
    arb.USDT,
    await xWinSwapV3.getAddress(),
    await xWinPriceMaster.getAddress(),
    arb.USDC,
    arb.aUSDT,
    arb.aavePool,
    arb.aavePoolDataProvider,
    xWinEmitEvent
  );
  
  
  let xWBTC = await deployxWinSingleAsset(
    "xWBTC Derivative", 
    "xWBTC", 
    arb.WBTC, 
    await xWinSwapV3.getAddress(),
    await xWinPriceMaster.getAddress(),
    arb.USDC, 
    arb.aWBTC, 
    arb.aavePool, 
    arb.aavePoolDataProvider,
    xWinEmitEvent
  );
  

  // const xWinDCA = await deployxWinDCA(
  //   arb.USDC,
  //   await xUSDC.getAddress(),
  //   await xWBTC.getAddress(),
  //   xWinSwapV3,
  //   xWinPriceMaster,
  //   xWinEmitEvent
  // );
  // const xWinTokenAlpha = await deployxWinTokenAlpha(
  //   arb.USDC,
  //   await xUSDT.getAddress(),
  //   await xWBTC.getAddress(),
  //   "USDT-WBTC Alpha",
  //   "UBA",
  //   xWinSwapV3,
  //   xWinPriceMaster,
  //   xWinEmitEvent
  // );

  // await xWinPriceMaster.addPrice(
  //   await xWinTokenAlpha.getAddress(),
  //   arb.USDC,
  //   3,
  //   arb.address0
  // );
  // await xWinPriceMaster.addPrice(
  //   await xWBTC.getAddress(),
  //   arb.USDC,
  //   3,
  //   arb.address0
  // );
  // await xWinPriceMaster.addPrice(
  //   await xUSDT.getAddress(),
  //   arb.USDC,
  //   3,
  //   arb.address0
  // );
  // await xWinPriceMaster.addPrice(
  //   await xWinDCA.getAddress(),
  //   arb.USDC,
  //   3,
  //   arb.address0
  // );

  // const fundV2Factory = await ethers.getContractFactory("FundV2");
  // await xWinFundV2Factory.createFund(
  //   "Test Fund 1",
  //   "TF1",
  //   arb.USDT,
  //   await accounts[1].getAddress(),
  //   await owner.getAddress(),
  //   arb.USDT
  // );
  // let fundIndex = await xWinFundV2Factory.getLatestFundID();
  // await xWinFundV2Factory.initialiseFund(
  //   fundIndex,
  //   100,
  //   2000,
  //   true,
  //   100,
  //   arb.PlatformAddress
  // );
  // let fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);

  // const fundV2Default1 = fundV2Factory.attach(fundAddr);

  // await xWinFundV2Factory.createFund(
  //   "Test Fund 2",
  //   "TF2",
  //   arb.USDT,
  //   await accounts[1].getAddress(),
  //   await owner.getAddress(),
  //   arb.USDT
  // );
  // fundIndex = await xWinFundV2Factory.getLatestFundID();
  // await xWinFundV2Factory.initialiseFund(
  //   fundIndex,
  //   100,
  //   2000,
  //   true,
  //   100,
  //   arb.PlatformAddress
  // );
  // fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);

  // const fundV2Default2 = fundV2Factory.attach(fundAddr);

  // await swapBNB("100", arb.USDT, await owner.getAddress());
  // await swapBNB("50", arb.WBTC, await owner.getAddress());
  // await swapBNB("50", arb.USDC, await owner.getAddress());
  // // await swapBNB("50", arb.xWinToken, await owner.getAddress());
  // await swapBNB("100", arb.USDT, await accounts[0].getAddress());
  // await swapBNB("50", arb.WBTC, await accounts[0].getAddress());
  // await swapBNB("50", arb.USDC, await accounts[0].getAddress());
  // // await swapBNB("50", arb.xWinToken, await accounts[0].getAddress());

  const USDT = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    arb.USDT
  );
  const WBTC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    arb.WBTC
  );
  const USDC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    arb.USDC
  );
  
  return {
    owner,
    accounts,
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent,
    xWinFundV2Factory,
    xWinMasterChef,
    xWinLockStaking,
    xUSDT,
    xWBTC,
    xWinDCA,
    xWinTokenAlpha,
    fundV2Default1,
    fundV2Default2,
    USDT,
    WBTC,
    USDC,
    xUSDC,
    // xWinToken,
  };
}

module.exports = {
  xWinFixture,
};