const {
  deployxWinSwapV3,
  deployTWAP,
  deployxWinEmitEvent,
  deployxWinDCA,
  deployxWinTokenAlpha,
  deployxWinPriceMaster,
  deployxWinSingleAsset,
  swapETH,
  deployFundV2Factory,
} = require("./xWinTestHelpers.js");
const { polygon } = require("./polygonMainnetAddresses.js");
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

  // deploy factory contract
  const xWinFundV2Factory = await deployFundV2Factory(
    xWinSwapV3,
    xWinEmitEvent,
    xWinPriceMaster,
    polygon.address0
  );

  // ======== core setup completed =============

  // deploy funds and strategy contracts
  const xUSDC = await deployxWinSingleAsset(
    "xUSDC Derivative",
    "xUSDC",
    polygon.USDC,
    xWinSwapV3,
    xWinPriceMaster,
    polygon.USDC,
    polygon.aUSDC,
    polygon.aavePool,
    polygon.aavePoolDataProvider,
    xWinEmitEvent
  );
  

  const xUSDT = await deployxWinSingleAsset(
    "xUSDT Derivative",
    "xUSDT",
    polygon.USDT,
    xWinSwapV3,
    xWinPriceMaster,
    polygon.USDC,
    polygon.aUSDT,
    polygon.aavePool,
    polygon.aavePoolDataProvider,
    xWinEmitEvent
  );
  
  
  let xWBTC = await deployxWinSingleAsset(
    "xWBTC Derivative", 
    "xWBTC", 
    polygon.WBTC, 
    xWinSwapV3,
    xWinPriceMaster,
    polygon.USDC, 
    polygon.aWBTC, 
    polygon.aavePool, 
    polygon.aavePoolDataProvider,
    xWinEmitEvent
  );
  
  const xWinDCA = await deployxWinDCA(
    polygon.USDC,
    await xUSDC.getAddress(),
    await xWBTC.getAddress(),
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent
  );
  const xWinTokenAlpha = await deployxWinTokenAlpha(
    polygon.USDC,
    await xUSDC.getAddress(),
    await xWBTC.getAddress(),
    "USDT-WBTC Alpha",
    "UBA",
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent
  );

  const fundV2Factory = await ethers.getContractFactory("FundV2");
  await xWinFundV2Factory.createFund(
    "Test Fund 1",
    "TF1",
    polygon.USDC,
    await accounts[1].getAddress(),
    await owner.getAddress(),
    polygon.USDC
  );
  let fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    polygon.PlatformAddress
  );
  let fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);
  console.log(fundAddr, "fundV2Default1 created")
  const fundV2Default1 = fundV2Factory.attach(fundAddr);

  await xWinFundV2Factory.createFund(
    "Test Fund 2",
    "TF2",
    polygon.USDC,
    await accounts[1].getAddress(),
    await owner.getAddress(),
    polygon.USDC
  );
  fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    polygon.PlatformAddress
  );
  fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);
  console.log(fundAddr, "fundV2Default2 created")
  
  const fundV2Default2 = fundV2Factory.attach(fundAddr);

  await swapETH("300", polygon.USDT, await owner.getAddress());
  await swapETH("1500", polygon.WBTC, await owner.getAddress());
  await swapETH("4000", polygon.USDC, await owner.getAddress());
  await swapETH("300", polygon.USDT, await accounts[0].getAddress());
  await swapETH("1500", polygon.WBTC, await accounts[0].getAddress());
  await swapETH("2000", polygon.USDC, await accounts[0].getAddress());

  const USDT = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    polygon.USDT
  );
  const WBTC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    polygon.WBTC
  );
  const USDC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    polygon.USDC
  );
  return {
    owner,
    accounts,
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent,
    xWinFundV2Factory,
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
  };
}

module.exports = {
  xWinFixture,
};
