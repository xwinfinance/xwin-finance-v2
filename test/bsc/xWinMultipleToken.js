const { expect } = require("chai");
const { ethers, upgrades, network } = require("hardhat");
const {
  loadFixture,
  impersonateAccount,
  setBalance,
} = require("@nomicfoundation/hardhat-network-helpers");

const { bsc } = require("./bscMainnetAddresses.js");

const DCABTCAddr = "0xa0c558C95a400fCCF5348e3301715a0AE95782d1";
const SWAP_ADDR = "0x9Ce3fCffaeB4B7Fbdf39E9313F845d977393D8d1";

// Replace with real whales that have balances on BSC at your fork block
const USDC_WHALE = "0x12b230F1CE31852907Ff162E37b1B02fcBdcf49f"; // <-- change
const USDT_WHALE = "0xba99D0A2016F43dA2c8AeB581b6076C8b487401A"; // <-- change

async function fundUser(token, whale, user, amount) {
  await impersonateAccount(whale);
  await setBalance(whale, ethers.parseEther("2")); // gas

  const whaleSigner = await ethers.getSigner(whale);
  await (
    await token.connect(whaleSigner).transfer(await user.getAddress(), amount)
  ).wait();

  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [whale],
  });
}

describe("xWinMultipleToken", function () {
  async function deployFixture() {
    const [owner, user, other] = await ethers.getSigners();

    const USDT = await ethers.getContractAt(
      "contracts/Interface/IBEP20.sol:IBEP20",
      bsc.USDT
    );

    const USDC = await ethers.getContractAt(
      "contracts/Interface/IBEP20.sol:IBEP20",
      bsc.USDC
    );

    const fund = await ethers.getContractAt("xWinDCAArb", DCABTCAddr);
    const swap = await ethers.getContractAt("xWinSwapV3Pancake", SWAP_ADDR);

    const xWinMDCFactory = await ethers.getContractFactory(
      "xWinMultipleToken"
    );

    const xWinMDC = await upgrades.deployProxy(xWinMDCFactory, [
      await swap.getAddress(),
      bsc.USDC,
    ]);

    console.log(`deployed to ${await xWinMDC.getAddress()}`);

    await (await xWinMDC.setSupportedToken(bsc.USDC, true)).wait();
    await (await xWinMDC.setSupportedToken(bsc.USDT, true)).wait();
    await (await xWinMDC.setSupportedFund(DCABTCAddr, true)).wait();

    // Amounts based on live decimals
    const usdcDecimals = await USDC.decimals();
    const usdtDecimals = await USDT.decimals();

    const DEPOSIT_USDC = ethers.parseUnits("20", usdcDecimals);
    const DEPOSIT_USDT = ethers.parseUnits("20", usdtDecimals);

    if (USDC_WHALE !== ethers.AddressZero) {
      await fundUser(USDC, USDC_WHALE, user, DEPOSIT_USDC);
    }
    if (USDT_WHALE !== ethers.AddressZero) {
      await fundUser(USDT, USDT_WHALE, user, DEPOSIT_USDT);
    }

    return {
      owner,
      user,
      other,
      USDC,
      USDT,
      swap,
      fund,
      xWinMDC,
      DEPOSIT_USDC,
      DEPOSIT_USDT,
    };
  }

  it("deposit USDC -> user receives fund shares", async function () {
    const { user, USDC, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    const sharesBefore = await fund.balanceOf(await user.getAddress());
    const usdcBefore = await USDC.balanceOf(await user.getAddress());

    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();

    await expect(
      xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).to.not.be.reverted;

    const sharesAfter = await fund.balanceOf(await user.getAddress());
    const usdcAfter = await USDC.balanceOf(await user.getAddress());

    expect(usdcAfter).to.lt(usdcBefore);
    expect(sharesAfter).to.gt(sharesBefore);
  });

  it("deposit USDT (swap path) -> user receives fund shares", async function () {
    const { user, USDT, fund, xWinMDC, DEPOSIT_USDT } = await loadFixture(
      deployFixture
    );

    const sharesBefore = await fund.balanceOf(await user.getAddress());    
    const usdtBefore = await USDT.balanceOf(await user.getAddress());

    await (
      await USDT.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDT)
    ).wait();

    await expect(
      xWinMDC
        .connect(user)
        ["deposit(uint256,uint32,address,address)"](
          DEPOSIT_USDT,
          300,
          bsc.USDT,
          DCABTCAddr
        )
    ).to.not.be.reverted;

    const sharesAfter = await fund.balanceOf(await user.getAddress());
    const usdtAfter = await USDT.balanceOf(await user.getAddress());

    expect(usdtAfter).to.lt(usdtBefore);
    expect(sharesAfter).to.gt(sharesBefore);
  });

  it("withdraw shares -> receive USDC (baseToken path)", async function () {
    const { user, USDC, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    // deposit first to get shares
    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const shares = await fund.balanceOf(await user.getAddress());
    expect(shares).to.gt(0);

    const withdrawAmt = shares / 2n;

    const usdcBefore = await USDC.balanceOf(await user.getAddress());
    const sharesBefore = await fund.balanceOf(await user.getAddress());

    await (
      await fund.connect(user).approve(await xWinMDC.getAddress(), withdrawAmt)
    ).wait();

    await expect(
      xWinMDC
        .connect(user)
        ["withdraw(uint256,uint32,address,address)"](
          withdrawAmt,
          200,
          bsc.USDC,
          DCABTCAddr
        )
    ).to.not.be.reverted;

    const usdcAfter = await USDC.balanceOf(await user.getAddress());
    const sharesAfter = await fund.balanceOf(await user.getAddress());

    expect(sharesAfter).to.lt(sharesBefore);
    expect(usdcAfter).to.gt(usdcBefore);
  });

  it("withdraw shares -> receive USDT (swap path)", async function () {
    const { user, USDC, USDT, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    // deposit USDC -> shares
    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const shares = await fund.balanceOf(await user.getAddress());
    expect(shares).to.gt(0);

    const withdrawAmt = shares / 2n;

    const usdtBefore = await USDT.balanceOf(await user.getAddress());
    const sharesBefore = await fund.balanceOf(await user.getAddress());

    await (
      await fund.connect(user).approve(await xWinMDC.getAddress(), withdrawAmt)
    ).wait();

    await expect(
      xWinMDC
        .connect(user)
        ["withdraw(uint256,address,address)"](withdrawAmt, bsc.USDT, DCABTCAddr)
    ).to.not.be.reverted;

    const usdtAfter = await USDT.balanceOf(await user.getAddress());
    const sharesAfter = await fund.balanceOf(await user.getAddress());

    expect(sharesAfter).to.lt(sharesBefore);
    expect(usdtAfter).to.gt(usdtBefore);
  });

  it("reverts if unsupported token/fund", async function () {
    const { user, xWinMDC, DEPOSIT_USDC } = await loadFixture(deployFixture);

    await expect(
      xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](
          DEPOSIT_USDC,
          "0x0000000000000000000000000000000000000000",
          DCABTCAddr
        )
    ).to.be.revertedWith("TOKEN_NOT_SUPPORTED");

    await expect(
      xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](
          DEPOSIT_USDC,
          bsc.USDC,
          "0x0000000000000000000000000000000000000000"
        )
    ).to.be.revertedWith("FUND_NOT_SUPPORTED");
  });

  it("router should not retain funds after USDC deposit (no USDC dust, no shares dust)", async function () {
    const { user, USDC, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const routerUsdc = await USDC.balanceOf(await xWinMDC.getAddress());
    const routerShares = await fund.balanceOf(await xWinMDC.getAddress());
    // Ideally 0. If you see tiny dust sometimes, change to <= 1 or <= small threshold.
    expect(routerUsdc).to.eq(0);
    expect(routerShares).to.eq(0);
  });

  it("router should not retain funds after USDT deposit (no USDT dust, no USDC dust, no shares dust)", async function () {
    const { user, USDT, USDC, fund, xWinMDC, DEPOSIT_USDT } = await loadFixture(
      deployFixture
    );

    await (
      await USDT.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDT)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,uint32,address,address)"](
          DEPOSIT_USDT,
          300,
          bsc.USDT,
          DCABTCAddr
        )
    ).wait();

    const routerUsdt = await USDT.balanceOf(await xWinMDC.getAddress());
    const routerUsdc = await USDC.balanceOf(await xWinMDC.getAddress());
    const routerShares = await fund.balanceOf(await xWinMDC.getAddress());

    expect(routerUsdt).to.eq(0);
    expect(routerUsdc).to.eq(0);
    expect(routerShares).to.eq(0);
  });

  it("router should not retain funds after withdraw to USDC", async function () {
    const { user, USDC, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    // deposit -> shares
    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const shares = await fund.balanceOf(await user.getAddress());
    const withdrawAmt = shares / 2n;

    await (
      await fund.connect(user).approve(await xWinMDC.getAddress(), withdrawAmt)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["withdraw(uint256,uint32,address,address)"](
          withdrawAmt,
          200,
          bsc.USDC,
          DCABTCAddr
        )
    ).wait();

    expect(await USDC.balanceOf(await xWinMDC.getAddress())).to.eq(0);
    expect(await fund.balanceOf(await xWinMDC.getAddress())).to.eq(0);
  });

  it("router should not retain funds after withdraw to USDT", async function () {
    const { user, USDC, USDT, fund, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    // deposit -> shares
    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const shares = await fund.balanceOf(await user.getAddress());
    const withdrawAmt = shares / 2n;

    await (
      await fund.connect(user).approve(await xWinMDC.getAddress(), withdrawAmt)
    ).wait();
    await (
      await xWinMDC
        .connect(user)
        ["withdraw(uint256,address,address)"](withdrawAmt, bsc.USDT, DCABTCAddr)
    ).wait();

    expect(await USDT.balanceOf(await xWinMDC.getAddress())).to.eq(0);
    expect(await USDC.balanceOf(await xWinMDC.getAddress())).to.eq(0);
    expect(await fund.balanceOf(await xWinMDC.getAddress())).to.eq(0);
  });

  it("deposit reverts when amount is zero", async function () {
    const { user, xWinMDC } = await loadFixture(deployFixture);

    await expect(
      xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](0, bsc.USDC, DCABTCAddr)
    ).to.be.revertedWith("Amount must be greater than zero");
  });

  it("withdraw reverts when amount is zero", async function () {
    const { user, xWinMDC } = await loadFixture(deployFixture);

    await expect(
      xWinMDC
        .connect(user)
        ["withdraw(uint256,address,address)"](0, bsc.USDC, DCABTCAddr)
    ).to.be.revertedWith("No balance to withdraw");
  });

  it("withdraw reverts when amount exceeds share balance", async function () {
    const { user, fund, xWinMDC } = await loadFixture(deployFixture);

    const shares = await fund.balanceOf(await user.getAddress()); // probably 0 at start
    await expect(
      xWinMDC
        .connect(user)
        ["withdraw(uint256,address,address)"](
          shares + 1n,
          bsc.USDC,
          DCABTCAddr
        )
    ).to.be.revertedWith("Withdraw amount exceeds balance");
  });

  it("USDC allowance router->fund ends unchanged after deposit (increase then spend)", async function () {
    const { user, USDC, xWinMDC, DEPOSIT_USDC } = await loadFixture(
      deployFixture
    );

    await (
      await USDC.connect(user).approve(await xWinMDC.getAddress(), DEPOSIT_USDC * 2n)
    ).wait();

    const before = await USDC.allowance(await xWinMDC.getAddress(), DCABTCAddr);

    await (
      await xWinMDC
        .connect(user)
        ["deposit(uint256,address,address)"](DEPOSIT_USDC, bsc.USDC, DCABTCAddr)
    ).wait();

    const after = await USDC.allowance(await xWinMDC.getAddress(), DCABTCAddr);

    expect(after).to.eq(before);
  });
});
