const { arb, hardhatNode } = require("./arbMainnetAddresses.js");
const { expect } = require("chai");

const swapETH = async (ethAmount, to, receiverAddress) => {
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
  console.log("TWAP Oracle deployed to address:", await twap.getAddress());
  return twap;
};

const deployxWinSwapV3 = async (signer) => {
  let xWinSwapFactory = await ethers.getContractFactory("xWinSwapV3");
  let xWinSwap = await upgrades.deployProxy(xWinSwapFactory, []);
  console.log("xWinSwap proxy deployed to:", await xWinSwap.getAddress());
  const slippage = 450;
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
      slippage,
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
      slippage,
      0,
      2
    );

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
      slippage,
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
      slippage,
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
      slippage,
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
      slippage,
      0,
      2
    );

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
      slippage,
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
      slippage,
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
  
  await xWinPrice.addPrice(
    addr,
    arb.USDC,
    3,
    arb.address0
  );

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

  await xWinPriceMaster.addPrice(
    await xWinDCA.getAddress(),
    arb.USDC,
    3,
    arb.address0
  );

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
    baseTokenAddr,
    name,
    symbol,
    0,
    1000,
    28800 * 5,
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

  await xWinPriceMaster.addPrice(
    await xWinTokenAlpha.getAddress(),
    arb.USDC,
    3,
    arb.address0
  );

  return xWinTokenAlpha;
};

const deployFundV2Factory = async (
  xWinSwap,
  xWinEmitEvent,
  xWinPriceMaster,
) => {
  const fundV2Deploy = await ethers.getContractFactory("FundV2");
  const FundFactoryDeploy = await ethers.getContractFactory("FundV2Factory");
  let beacon = await upgrades.deployBeacon(fundV2Deploy);
  console.log("FundV2 Beacon Deployed!");
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
  swapETH,
  deployFundV2Factory,
  expectAlmostEquals,
};
