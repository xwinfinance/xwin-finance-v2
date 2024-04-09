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
const { arb } = require("./arbMainnetAddresses.js");
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
    arb.address0
  );

  // ======== core setup completed =============

  // deploy funds and strategy contracts
  const xUSDC = await deployxWinSingleAsset(
    "xUSDC Derivative",
    "xUSDC",
    arb.USDC,
    xWinSwapV3,
    xWinPriceMaster,
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
    xWinSwapV3,
    xWinPriceMaster,
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
    xWinSwapV3,
    xWinPriceMaster,
    arb.USDC, 
    arb.aWBTC, 
    arb.aavePool, 
    arb.aavePoolDataProvider,
    xWinEmitEvent
  );
  
  const xWinDCA = await deployxWinDCA(
    arb.USDC,
    await xUSDC.getAddress(),
    await xWBTC.getAddress(),
    xWinSwapV3,
    xWinPriceMaster,
    xWinEmitEvent
  );
  const xWinTokenAlpha = await deployxWinTokenAlpha(
    arb.USDC,
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
    arb.USDC,
    await accounts[1].getAddress(),
    await owner.getAddress(),
    arb.USDC
  );
  let fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    arb.PlatformAddress
  );
  let fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);
  console.log(fundAddr, "fundV2Default1 created")
  const fundV2Default1 = fundV2Factory.attach(fundAddr);

  await xWinFundV2Factory.createFund(
    "Test Fund 2",
    "TF2",
    arb.USDC,
    await accounts[1].getAddress(),
    await owner.getAddress(),
    arb.USDC
  );
  fundIndex = await xWinFundV2Factory.getLatestFundID();
  await xWinFundV2Factory.initialiseFund(
    fundIndex,
    100,
    2000,
    true,
    100,
    arb.PlatformAddress
  );
  fundAddr = await xWinFundV2Factory.getFundfromIndex(fundIndex);
  console.log(fundAddr, "fundV2Default2 created")
  
  const fundV2Default2 = fundV2Factory.attach(fundAddr);

  await swapETH("100", arb.USDT, await owner.getAddress());
  await swapETH("500", arb.WBTC, await owner.getAddress());
  await swapETH("200", arb.USDC, await owner.getAddress());
  await swapETH("100", arb.USDT, await accounts[0].getAddress());
  await swapETH("500", arb.WBTC, await accounts[0].getAddress());
  await swapETH("200", arb.USDC, await accounts[0].getAddress());

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
