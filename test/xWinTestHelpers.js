const { bsc, hardhatNode } = require("../bscMainnetAddresses.js");
const { expect } = require("chai");

const swapBNB = async (bnbAmount, to, receiverAddress) => {
  let wbnbERC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    bsc.WBNB
  );
  let wbnbToken = await ethers.getContractAt(
    "contracts/Interface/IWETH.sol:IWETH",
    bsc.WBNB
  );
  let pancake = await ethers.getContractAt(
    "contracts/Interface/AllPancakeInterface.sol:IPancakeRouter02",
    bsc.pancakeRouter
  );

  let res = await wbnbToken.deposit({
    value: ethers.parseEther(bnbAmount),
  });
  let pancakeAmounts = await pancake.getAmountsOut(
    ethers.parseEther(bnbAmount),
    [bsc.WBNB, to]
  );
  let amount =
    pancakeAmounts[1] - (pancakeAmounts[1] * BigInt(50)) / BigInt(10000);
  res = await wbnbERC.approve(bsc.pancakeRouter, ethers.parseEther(bnbAmount));
  res = await pancake.swapExactTokensForTokens(
    ethers.parseEther(bnbAmount),
    amount,
    [bsc.WBNB, to],
    receiverAddress,
    Date.now()
  );
};

const deployxWinPriceMaster = async (signer, swapAddr, twapAddr) => {
  // 1. deploy xWinPriceMaster
  let xWinPriceMasterFactory = await ethers.getContractFactory(
    "xWinPriceMaster"
  );
  let xWinPriceMaster = await upgrades.deployProxy(xWinPriceMasterFactory, [
    swapAddr,
    twapAddr,
  ]);
  console.log(
    "xWinPriceMaster proxy deployed to:",
    await xWinPriceMaster.getAddress()
  );
  console.log(
    "xWinPriceMaster implementation deployed to:",
    await upgrades.erc1967.getImplementationAddress(
      await xWinPriceMaster.getAddress()
    )
  );

  await xWinPriceMaster.setExecutor(await signer.getAddress(), true);

  // setup chainlink usd prices
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.WBNB, bsc.chainLinkBNBUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.BTCB, bsc.chainLinkBTCUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.ETH, bsc.chainLinkETHUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.ADA, bsc.chainLinkADAUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.XVS, bsc.chainLinkXVSUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.XRP, bsc.chainLinkXRPUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.BSW, bsc.chainLinkBSWUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.UNI, bsc.chainLinkUNIUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.LINK, bsc.chainLinkLINKUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.CAKE, bsc.chainLinkCAKEUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.USDC, bsc.chainLinkUSDCUSDT);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(bsc.USDT, bsc.chainLinkUSDTUSD);
  // 1. Setup price feed
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.WBNB, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.BTCB, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.ETH, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.ADA, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.XVS, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.BSW, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.UNI, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.LINK, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.CAKE, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.USDC, bsc.USDT, 1, bsc.address0); //chainlink
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.xWinToken, bsc.USDT, 5, bsc.address0); // twap
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.USDT, bsc.xWinToken, 5, bsc.address0); // twap
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.XWIN_BNB_pancakeLP, bsc.USDT, 4, bsc.address0); // LP price
  await xWinPriceMaster
    .connect(signer)
    .addPrice(bsc.XWIN_USDT_ApeLP, bsc.USDT, 4, bsc.address0); // LP price
  return xWinPriceMaster;
};

const deployTWAP = async () => {
  const twapFactory = await ethers.getContractFactory("UniSwapV2TWAPOracle");
  const twap = await twapFactory.deploy(bsc.WBNB);
  await twap.setPeriod(5);
  await twap.addPair(bsc.XWIN_USDT_babyLP);
  await new Promise((resolve) => setTimeout(resolve, 6000));
  await twap.massUpdate();
  console.log("TWAP Oracle deployed to address:", await twap.getAddress());
  return twap;
};

const deployxWinSwapV3 = async (signer) => {
  let xWinSwapFactory = await ethers.getContractFactory("xWinSwapV3Pancake");
  let xWinSwap = await upgrades.deployProxy(xWinSwapFactory, []);
  console.log("xWinSwap proxy deployed to:", await xWinSwap.getAddress());

  await xWinSwap.setExecutor(await signer.getAddress(), true);

  // 2. Setup USDT-BTCB
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.BTCB,
      bsc.pancakeSmartRouter,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [bsc.USDT, 500, bsc.WBNB, 2500, bsc.BTCB]
      ),
      100,
      0,
      2
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.BTCB,
      bsc.USDT,
      bsc.pancakeSmartRouter,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [bsc.BTCB, 2500, bsc.WBNB, 500, bsc.USDT]
      ),
      100,
      0,
      2
    );

  // 3. Setup USDT-XVS
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.XVS,
      bsc.pancakeRouter,
      [bsc.USDT, bsc.WBNB, bsc.XVS],
      "0x0000000000",
      500,
      0,
      0
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.XVS,
      bsc.USDT,
      bsc.pancakeRouter,
      [bsc.XVS, bsc.WBNB, bsc.USDT],
      "0x0000000000",
      500,
      0,
      0
    );

  // 4. Setup USDT-ADA
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.ADA,
      bsc.pancakeRouter,
      [bsc.USDT, bsc.WBNB, bsc.ADA],
      "0x0000000000",
      100,
      0,
      0
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.ADA,
      bsc.USDT,
      bsc.pancakeRouter,
      [bsc.ADA, bsc.WBNB, bsc.USDT],
      "0x0000000000",
      100,
      0,
      0
    );

  // 5. Setup USDT-ETH
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.ETH,
      bsc.pancakeSmartRouter,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [bsc.USDT, 500, bsc.WBNB, 2500, bsc.ETH]
      ),
      100,
      0,
      2
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.ETH,
      bsc.USDT,
      bsc.pancakeSmartRouter,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [bsc.ETH, 2500, bsc.WBNB, 500, bsc.USDT]
      ),
      100,
      0,
      2
    );


  // 6. Setup USDT-CAKE
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.CAKE,
      bsc.USDT,
      bsc.pancakeSmartRouter,
      [],
      "0x0000000000",
      100,
      2500,
      1
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.CAKE,
      bsc.pancakeSmartRouter,
      [],
      "0x0000000000",
      100,
      2500,
      1
    );

  // 7. Setup USDT-WBNB
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.WBNB,
      bsc.USDT,
      bsc.pancakeSmartRouter,
      [],
      "0x0000000000",
      100,
      500,
      1
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      bsc.USDT,
      bsc.WBNB,
      bsc.pancakeSmartRouter,
      [],
      "0x0000000000",
      100,
      500,
      1
    );
  return xWinSwap;
};

const deployxWinSingleAsset = async (
  name,
  symbol,
  xWinSwap,
  lendingRewardToken,
  xWinPrice,
  baseToken,
  stablecoinAddr,
  managerFee = 0,
  performanceFee = 0
) => {
  // 2. deploy xWinSingleAsset for BTCB
  let xWinSingleAssetFactory = await ethers.getContractFactory(
    "xWinSingleAsset"
  );
  let xWinSingleAsset = await upgrades.deployProxy(xWinSingleAssetFactory, [
    name,
    symbol,
    baseToken,
    stablecoinAddr,
    managerFee,
    performanceFee,
    28800 * 30,
    hardhatNode.publicAddress3,
  ]);
  await xWinSingleAsset.init(
    await xWinSwap.getAddress(),
    lendingRewardToken,
    await xWinPrice.getAddress()
  );
  console.log(
    symbol,
    " proxy deployed to address:",
    await xWinSingleAsset.getAddress()
  );
  await xWinSwap.registerStrategyContract(await xWinSingleAsset.getAddress(), baseToken);

  return xWinSingleAsset;
};

const deployxWinEmitEvent = async () => {
  let xWinEventFactory = await ethers.getContractFactory("xWinEmitEvent");
  let xWinEvent = await upgrades.deployProxy(xWinEventFactory, []);
  console.log("xWinEvent proxy deployed to:", await xWinEvent.getAddress());
  console.log(
    "xWinEvent implementation deployed to:",
    await upgrades.erc1967.getImplementationAddress(
      await xWinEvent.getAddress()
    )
  );
  return xWinEvent;
};

const deployxWinDCA = async (
  baseTokenAddr,
  baseStakingTokenAddr,
  targetTokenAddr,
  xWinSwap,
  xWinPriceMaster,
  xWinEmitEvent
) => {
  let xWinDCAFactory = await ethers.getContractFactory("xWinDCA");
  const xWinDCA = await upgrades.deployProxy(xWinDCAFactory, [
    baseTokenAddr,
    targetTokenAddr,
    await xWinSwap.getAddress(),
    await xWinPriceMaster.getAddress(),
    baseStakingTokenAddr,
    bsc.USDT,
    0,
    0,
    28800 * 30,
    hardhatNode.publicAddress3,
  ]);
  const xWinDCAAddr = await xWinDCA.getAddress();
  console.log("xWinDollarCostAverage deployed to address:", xWinDCAAddr);

  // update emit event contract
  await xWinEmitEvent.setExecutor(xWinDCAAddr, true);
  await xWinDCA.setEmitEvent(await xWinEmitEvent.getAddress());

  await xWinDCA.setExecutor(hardhatNode.publicAddress2, true);
  await xWinSwap.registerStrategyContract(xWinDCAAddr, bsc.USDT);

  return xWinDCA;
};

const deployxWinTokenAlpha = async (
  baseTokenAddr,
  baseStakingTokenAddr,
  targetTokenAddr,
  name,
  symbol,
  xWinSwap,
  xWinPriceMaster,
  xWinEmitEvent
) => {
  const xWinTokenAlphaFactory = await ethers.getContractFactory(
    "xWinERC20Alpha"
  );
  const xWinTokenAlpha = await upgrades.deployProxy(xWinTokenAlphaFactory, [
    baseTokenAddr,
    bsc.USDT,
    name,
    symbol,
    0,
    0,
    28800 * 30,
    hardhatNode.publicAddress3,
  ]);
  await xWinTokenAlpha.init(
    targetTokenAddr,
    await xWinSwap.getAddress(),
    baseStakingTokenAddr,
    await xWinPriceMaster.getAddress()
  );
  const xWinTokenAlphaAddr = await xWinTokenAlpha.getAddress();
  console.log("xWinAdaTokenAlpha deployed to address:", xWinTokenAlphaAddr);

  await xWinEmitEvent.setExecutor(xWinTokenAlphaAddr, true);
  await xWinTokenAlpha.setEmitEvent(await xWinEmitEvent.getAddress());
  //set executor
  await xWinTokenAlpha.setExecutor(hardhatNode.publicAddress2, true);
  await xWinSwap.registerStrategyContract(xWinTokenAlphaAddr, baseTokenAddr);

  return xWinTokenAlpha;
};

const deployFundV2Factory = async (
  xWinSwap,
  xWinEmitEvent,
  xWinPriceMaster,
  lockedStake
) => {
  const fundV2Deploy = await ethers.getContractFactory("FundV2");
  const FundFactoryDeploy = await ethers.getContractFactory("FundV2Factory");
  let beacon = await upgrades.deployBeacon(fundV2Deploy);
  console.log("FundV2 Beacon Deployed!");
  console.log("lock", await lockedStake.getAddress());
  const fundFactory = await upgrades.deployProxy(FundFactoryDeploy, [
    hardhatNode.publicAddress,
    await xWinSwap.getAddress(),
    await xWinPriceMaster.getAddress(),
    await xWinEmitEvent.getAddress(),
    await lockedStake.getAddress(),
    bsc.xWinToken,
    await beacon.getAddress(),
    bsc.USDT,
    bsc.ManagerAddress,
    bsc.PlatformAddress,
  ]);
  console.log("FundV2 Factory Deployed", await fundFactory.getAddress());
  xWinEmitEvent.setAdmin(await fundFactory.getAddress(), true);
  await fundFactory.addNewBaseToken(bsc.USDT);
  // add admins to strategyInteractor
  await xWinSwap.setAdmin(await fundFactory.getAddress(), true);
  console.log("FundV2 Factory Setup Done!");
  return fundFactory;
};

const deployxWinDefi = async (signer) => {
  // initialize new xwin defi protocol
  let xWinDefiFactory = await ethers.getContractFactory("xWinDefiProtocol");
  let xWinDefi = await xWinDefiFactory
    .connect(signer)
    .deploy(
      "0",
      await signer.getAddress(),
      await signer.getAddress(),
      await signer.getAddress(),
      bsc.xWinToken
    );
  await swapBNB("300", bsc.xWinToken, await xWinDefi.getAddress());
  console.log("xWINDEFI deployed to address:", await xWinDefi.getAddress());

  return xWinDefi;
};

const deployxWinMasterChef = async (xWinDefi, xWinPriceMaster) => {
  let xwinPerBlockInProtocol = "1000000000000000000";
  let xwinPerBlockInMasterChef = "10000000000000000";

  let xWinMasterChefFactory = await ethers.getContractFactory("xWinMasterChef");
  let xWinMasterChef = await upgrades.deployProxy(xWinMasterChefFactory, [
    "xWin Master Chef",
    "xWinMC",
    bsc.USDT,
    28800,
  ]);
  console.log(
    "xWinMasterChef proxy deployed to:",
    await xWinMasterChef.getAddress()
  );
  console.log(
    "xWinMasterChef implementation deployed to:",
    await upgrades.erc1967.getImplementationAddress(
      await xWinMasterChef.getAddress()
    )
  );

  // configure xwinDefi pool for xWinMasterChef
  let resAdd = await xWinDefi.add(
    await xWinMasterChef.getAddress(),
    xwinPerBlockInProtocol,
    "1"
  );
  const poolId = Number(await xWinDefi.poolLength()) - 1;

  // update xwindefi protocol address in xWinMasterChef
  resAdd = await xWinMasterChef.updateSmartContract(
    await xWinDefi.getAddress(),
    await xWinPriceMaster.getAddress()
  );

  // update xwinId in xWinMasterChef
  resAdd = await xWinMasterChef.updateProperties(
    bsc.xWinToken,
    poolId,
    xwinPerBlockInMasterChef
  );

  // admin farm dummy token into xWinDefi
  resAdd = await xWinMasterChef.farmTokenByAdmin();

  // 1. add XWIN pool ad default pool 0
  await xWinMasterChef.add(1000, bsc.xWinToken, "365");

  return xWinMasterChef;
};

const deployLockStaking = async (signer, xWinMasterChef) => {
  let lockedStakeFactory = await ethers.getContractFactory("xWinLockedStake");
  let lockedStake = await upgrades.deployProxy(lockedStakeFactory, [
    bsc.xWinToken,
    await xWinMasterChef.getAddress(),
    await signer.getAddress(),
    0,
    1,
  ]);
  console.log("lockedStake proxy deployed to:", await lockedStake.getAddress());

  // add another pool into xWinMasterChef pid: 1, points: 1000, duration: 1 year
  await xWinMasterChef.add(1000, await lockedStake.getAddress(), "365");

  await lockedStake.masterChefDeposit(); // lock rewards pid
  return lockedStake;
};

const expectAlmostEquals = (a,b) => {
  expect(a).gte(b * BigInt(99) / BigInt(100));
  expect(a).lte(b * BigInt(101) / BigInt(100));
}

module.exports = {
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
  expectAlmostEquals
};
