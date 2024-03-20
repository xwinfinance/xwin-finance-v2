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
  deployxWinDefi,
  deployxWinMasterChef,
  deployLockStaking,
} = require("./xWinTestHelpers.js");
const { bsc, hardhatNode } = require("../bscMainnetAddresses.js");
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

  // deploy farming/staking contracts
  const xWinDefi = await deployxWinDefi(owner);
  const xWinMasterChef = await deployxWinMasterChef(xWinDefi, xWinPriceMaster);
  const xWinLockStaking = await deployLockStaking(owner, xWinMasterChef);

  // deploy factory contract
  const xWinFundV2Factory = await deployFundV2Factory(
    xWinSwapV3,
    xWinEmitEvent,
    xWinPriceMaster,
    xWinLockStaking
  );

  // ======== core setup completed =============

  // deploy funds and strategy contracts
  const xUSDT = await deployxWinSingleAsset(
    "USDT Venus Staking",
    "xUSDT",
    xWinSwapV3,
    bsc.XVS,
    xWinPriceMaster,
    bsc.USDT,
    bsc.USDT
  );
  await xUSDT.updateProperties(bsc.venusUSDT, bsc.venusRainMaker);

  const xBTCB = await deployxWinSingleAsset(
    "BTCB Venus Staking",
    "xBTC",
    xWinSwapV3,
    bsc.XVS,
    xWinPriceMaster,
    bsc.BTCB,
    bsc.USDT
  );
  await xBTCB.updateProperties(bsc.venusBTC, bsc.venusRainMaker);

  const xWinDCA = await deployxWinDCA(
    bsc.USDT,
    await xUSDT.getAddress(),
    await xBTCB.getAddress(),
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent
  );
  const xWinTokenAlpha = await deployxWinTokenAlpha(
    bsc.USDT,
    await xUSDT.getAddress(),
    await xBTCB.getAddress(),
    "USDT-BTCB Alpha",
    "UBA",
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent
  );

  await xWinPriceMaster.addPrice(await xWinTokenAlpha.getAddress(), bsc.USDT, 3, bsc.address0);
  await xWinPriceMaster.addPrice(await xBTCB.getAddress(), bsc.USDT, 3, bsc.address0);
  await xWinPriceMaster.addPrice(await xUSDT.getAddress(), bsc.USDT, 3, bsc.address0);
  await xWinPriceMaster.addPrice(await xWinDCA.getAddress(), bsc.USDT, 3, bsc.address0);

  const fundV2Factory = await ethers.getContractFactory("FundV2");
  await xWinFundV2Factory.createFund(
    "Test Fund 1",
    "TF1",
    bsc.USDT,
    await accounts[1].getAddress(),
    await owner.getAddress(),
    bsc.USDT
  );
  let fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    bsc.PlatformAddress
  );
  let fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);

  const fundV2Default1 = fundV2Factory.attach(fundAddr);

  await xWinFundV2Factory.createFund(
    "Test Fund 2",
    "TF2",
    bsc.USDT,
    await accounts[5].getAddress(),
    await owner.getAddress(),
    bsc.USDT
  );
  fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    bsc.PlatformAddress
  );
  fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);

  const fundV2Default2 = fundV2Factory.attach(fundAddr);
  
  await swapBNB('100', bsc.USDT, await owner.getAddress());
  await swapBNB('50', bsc.BTCB, await owner.getAddress());
  await swapBNB('50', bsc.USDC, await owner.getAddress());
  await swapBNB('50', bsc.xWinToken, await owner.getAddress());
  await swapBNB('100', bsc.USDT, await accounts[0].getAddress());
  await swapBNB('50', bsc.BTCB, await accounts[0].getAddress());
  await swapBNB('50', bsc.USDC, await accounts[0].getAddress());
  await swapBNB('50', bsc.xWinToken, await accounts[0].getAddress());
  
  const USDT = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    bsc.USDT
  );
  const BTCB = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    bsc.BTCB
  );
  const USDC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    bsc.USDC
  );
  const xWinToken = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    bsc.xWinToken
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
    xBTCB,
    xWinDCA,
    xWinTokenAlpha,
    fundV2Default1,
    fundV2Default2,
    USDT,
    BTCB,
    USDC,
    xWinToken
  };
}

module.exports = {
  xWinFixture,
};
