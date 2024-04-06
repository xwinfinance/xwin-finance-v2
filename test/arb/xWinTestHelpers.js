const { arb, hardhatNode } = require("./arbMainnetAddresses.js");
const { expect } = require("chai");

const swapBNB = async (ethAmount, to, receiverAddress) => {
  let WETHERC = await ethers.getContractAt(
    "contracts/Interface/IBEP20.sol:IBEP20",
    arb.WETH
  );
  let WETH = await ethers.getContractAt(
    "contracts/Interface/IWETH.sol:IWETH",
    arb.WETH
  );
  let uniswapRouter = await ethers.getContractAt(
    "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol:ISwapRouter",
    arb.uniswapV3Router
  );

  await WETH.deposit({ value: ethers.parseEther(ethAmount) });
  await WETHERC.approve(
    arb.uniswapV3Router,
    ethers.parseEther(ethAmount)
  );

  const currentBlock = (await ethers.provider.getBlock()).timestamp;
  const params = {
    tokenIn: arb.WETH,
    tokenOut: to,
    fee: 500,
    recipient: receiverAddress,
    deadline: currentBlock + 1000,
    amountIn: ethers.parseEther(ethAmount),
    amountOutMinimum: 0,
    sqrtPriceLimitX96: 0,
  };
  await uniswapRouter.exactInputSingle(params);
  console.log("Swap done!");
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
    .addChainlinkUSDPrice(arb.WETH, arb.chainLinkETHUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.WBTC, arb.chainLinkBTCUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.UNI, arb.chainLinkUNIUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.LINK, arb.chainLinkLINKUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.USDT, arb.chainLinkUSDTUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.USDC, arb.chainLinkUSDCUSD);
  await xWinPriceMaster
    .connect(signer)
    .addChainlinkUSDPrice(arb.ARB, arb.chainLinkARBUSD);

  // 1. Setup price feed
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.WETH, arb.USDC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.WBTC, arb.USDC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.UNI, arb.USDC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.LINK, arb.USDC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDT, arb.USDC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.ARB, arb.USDC, 1, arb.address0);

  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.WETH, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.WBTC, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.UNI, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.LINK, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.USDT, 1, arb.address0);
  await xWinPriceMaster
    .connect(signer)
    .addPrice(arb.USDC, arb.ARB, 1, arb.address0);
  return xWinPriceMaster;
};

const deployTWAP = async () => {
  const twapFactory = await ethers.getContractFactory("UniSwapV2TWAPOracle");
  const twap = await twapFactory.deploy(arb.WETH);
  await twap.setPeriod(5);
  // await twap.addPair(arb.XWIN_USDT_babyLP);
  // await new Promise((resolve) => setTimeout(resolve, 6000));
  // await twap.massUpdate();
  // console.log("TWAP Oracle deployed to address:", await twap.getAddress());
  return twap;
};

const deployxWinSwapV3 = async (signer) => {
  let xWinSwapFactory = await ethers.getContractFactory("xWinSwapV3");
  let xWinSwap = await upgrades.deployProxy(xWinSwapFactory, []);
  console.log("xWinSwap proxy deployed to:", await xWinSwap.getAddress());

  await xWinSwap.setExecutor(await signer.getAddress(), true);

  // 2. Setup USDC-WBTC
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.USDC,
      arb.WBTC,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.USDC, 500, arb.WETH, 500, arb.WBTC]
      ),
      350,
      0,
      2
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.WBTC,
      arb.USDC,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.WBTC, 500, arb.WETH, 500, arb.USDC]
      ),
      250,
      0,
      2
    );

  // // Setup USDC-ETH
  // await xWinSwap.connect(signer).addTokenPath(arb.USDC, arb.WETH, arb.uniswapV3Router, [], [], 250, 500, 1);
  // await xWinSwap.connect(signer).addTokenPath(arb.WETH, arb.USDC, arb.uniswapV3Router, [], [], 250, 500, 1);
  // await xWinSwap
  //   .connect(signer)
  //   .addTokenPath(
  //     bsc.USDC,
  //     bsc.WETH,
  //     bsc.uniswapV3Router,
  //     [bsc.USDC, bsc.WETH],
  //     "0x0000000000",
  //     100,
  //     0,
  //     0
  //   );

  // Setup USDC-UNI
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.USDC,
      arb.UNI,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.USDC, 500, arb.WETH, 3000, arb.UNI]
      ),
      250,
      0,
      2
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.UNI,
      arb.USDC,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.UNI, 3000, arb.WETH, 500, arb.USDC]
      ),
      250,
      0,
      2
    );

  // Setup USDC-LINK
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.USDC,
      arb.LINK,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.USDC, 500, arb.WETH, 3000, arb.LINK]
      ),
      250,
      0,
      2
    );
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.LINK,
      arb.USDC,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.LINK, 3000, arb.WETH, 500, arb.USDC]
      ),
      250,
      0,
      2
    );

  // // USDC - USDT
  // await xWinSwap.connect(signer).addTokenPath(arb.USDC, arb.USDT, arb.uniswapV3Router, [], [], 250, 100, 1);
  // await xWinSwap.connect(signer).addTokenPath(arb.USDT, arb.USDC, arb.uniswapV3Router, [], [], 250, 100, 1);

  // USDC - COMP
  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.USDC,
      arb.ARB,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.USDC, 500, arb.WETH, 500, arb.ARB]
      ),
      250,
      0,
      2
    );

  await xWinSwap
    .connect(signer)
    .addTokenPath(
      arb.ARB,
      arb.USDC,
      arb.uniswapV3Router,
      [],
      ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [arb.ARB, 500, arb.WETH, 500, arb.USDC]
      ),
      250,
      0,
      2
    );
  console.log("done xWinSwap");
  return xWinSwap;
};

const deployxWinSingleAsset = async (
  name,
  symbol,
  baseToken,
  xWinSwap,
  xWinPrice,
  stablecoinAddr,
  targetToken,
  pool,
  aavePoolDataProvider,
  xWinEmitEvent
) => {
  // 2. deploy xWinSingleAsset for WBTC
  let xWinSingleAssetFactory = await ethers.getContractFactory(
    "xWinSingleAssetAave"
  );

  let xWinSingleAsset = await upgrades.deployProxy(xWinSingleAssetFactory, [
    name,
    symbol,
    baseToken,
    await xWinSwap.getAddress(),
    await xWinPrice.getAddress(),
    stablecoinAddr,
    0,
    0,
    28800 * 90,
    hardhatNode.publicAddress3,
  ]);

  await xWinSingleAsset.updateProperties(
    targetToken,
    pool,
    aavePoolDataProvider
  );

  const addr = await xWinSingleAsset.getAddress();
  // update emit event contract
  xWinEmitEvent.setExecutor(addr, true);
  xWinSingleAsset.setEmitEvent(await xWinEmitEvent.getAddress());

  await xWinSwap.registerStrategyContract(addr, baseToken);
  console.log(symbol, " proxy deployed to address:", addr);

  await xWinSingleAsset.setExecutor(hardhatNode.publicAddress, true);
  
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
  let xWinDCAFactory = await ethers.getContractFactory("xWinDCAArb");
  const xWinDCA = await upgrades.deployProxy(xWinDCAFactory, [
    baseTokenAddr,
    baseTokenAddr,
    20,
    1000,
    28800 * 5,
    hardhatNode.publicAddress3,
    "xDCA Btc",
    "xDCA.btc",
  ]);
  
  const xWinDCAAddr = await xWinDCA.getAddress();
  console.log("xWinDCA deployed to address:", xWinDCAAddr);
  await xWinDCA.init(
    targetTokenAddr, 
    await xWinSwap.getAddress(), 
    await baseStakingTokenAddr, 
    await xWinPriceMaster.getAddress());

  // update emit event contract
  await xWinEmitEvent.setExecutor(xWinDCAAddr, true);
  await xWinDCA.setEmitEvent(await xWinEmitEvent.getAddress());

  await xWinDCA.setExecutor(hardhatNode.publicAddress, true);
  await xWinSwap.registerStrategyContract(xWinDCAAddr, arb.USDC);

  await xWinDCA.updateProperties(ethers.parseEther("5000"), 90 * 28800, 28800);
  console.log("xDCA updateProperties!")

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
    arb.USDT,
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
  console.log("xWinTokenAlpha deployed to address:", xWinTokenAlphaAddr);

  await xWinEmitEvent.setExecutor(xWinTokenAlphaAddr, true);
  await xWinTokenAlpha.setEmitEvent(await xWinEmitEvent.getAddress());
  //set executor
  await xWinTokenAlpha.setExecutor(hardhatNode.publicAddress, true);
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
  // console.log("lock", await lockedStake.getAddress());
  const fundFactory = await upgrades.deployProxy(FundFactoryDeploy, [
    hardhatNode.publicAddress,
    await xWinSwap.getAddress(),
    await xWinPriceMaster.getAddress(),
    await xWinEmitEvent.getAddress(),
    arb.address0,
    arb.USDC,
    await beacon.getAddress(),
    arb.USDC,
    arb.ManagerAddress,
    arb.PlatformAddress,
  ]);
  console.log("FundV2 Factory Deployed", await fundFactory.getAddress());
  xWinEmitEvent.setAdmin(await fundFactory.getAddress(), true);
  await fundFactory.addNewBaseToken(arb.USDC);
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
      arb.xWinToken
    );
  await swapBNB("300", arb.xWinToken, await xWinDefi.getAddress());
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
    arb.USDT,
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
    arb.xWinToken,
    poolId,
    xwinPerBlockInMasterChef
  );

  // admin farm dummy token into xWinDefi
  resAdd = await xWinMasterChef.farmTokenByAdmin();

  // 1. add XWIN pool ad default pool 0
  await xWinMasterChef.add(1000, arb.xWinToken, "365");

  return xWinMasterChef;
};

const deployLockStaking = async (signer, xWinMasterChef) => {
  let lockedStakeFactory = await ethers.getContractFactory("xWinLockedStake");
  let lockedStake = await upgrades.deployProxy(lockedStakeFactory, [
    arb.xWinToken,
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

const expectAlmostEquals = (a, b) => {
  expect(a).gte((b * BigInt(99)) / BigInt(100));
  expect(a).lte((b * BigInt(101)) / BigInt(100));
};

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
  expectAlmostEquals,
};
