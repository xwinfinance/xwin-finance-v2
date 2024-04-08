const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { bsc, hardhatNode } = require("./bscMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseEther("1000");

describe("xWinSwap", function () {
  describe("Core", function () {
    it("Swaps", async function () {
      const { owner, accounts, xWinSwapV3, USDT, BTCB } = await loadFixture(
        xWinFixture
      );
      const WBNB = await ethers.getContractAt(
        "contracts/Interface/IBEP20.sol:IBEP20",
        bsc.WBNB
      );
      const XVS = await ethers.getContractAt(
        "contracts/Interface/IBEP20.sol:IBEP20",
        bsc.XVS
      );
      await USDT.approve(
        await xWinSwapV3.getAddress(),
        ethers.parseEther("10000")
      );
      await BTCB.approve(await xWinSwapV3.getAddress(), ethers.parseEther("1"));

      const balanceBTCBefore = await BTCB.balanceOf(await owner.getAddress());

      await xWinSwapV3.swapTokenToToken(defaultAmount, bsc.USDT, bsc.BTCB);
      await xWinSwapV3.swapTokenToToken(defaultAmount, bsc.USDT, bsc.WBNB);
      await xWinSwapV3.swapTokenToToken(defaultAmount, bsc.USDT, bsc.XVS);

      expectAlmostEquals(
        (await BTCB.balanceOf(await owner.getAddress())) - balanceBTCBefore,
        ethers.parseEther("0.0233")
      );
      expectAlmostEquals(
        await WBNB.balanceOf(await owner.getAddress()),
        ethers.parseEther("3.31")
      );
      expectAlmostEquals(
        await XVS.balanceOf(await owner.getAddress()),
        ethers.parseEther("84.1")
      );

      const balanceUSDTBefore = await USDT.balanceOf(await owner.getAddress());
      await xWinSwapV3.swapTokenToToken(
        ethers.parseEther("0.1"),
        bsc.BTCB,
        bsc.USDT
      );
      expectAlmostEquals(
        (await USDT.balanceOf(await owner.getAddress())) - balanceUSDTBefore,
        ethers.parseEther("4250")
      );
    });

    it("Swaps xWinStrategy", async function () {
      const { owner, accounts, xWinSwapV3, xBTCB, xWinDCA, USDT, BTCB } =
        await loadFixture(xWinFixture);
      await USDT.approve(
        await xWinSwapV3.getAddress(),
        ethers.parseEther("10000")
      );
      await BTCB.approve(await xWinSwapV3.getAddress(), ethers.parseEther("1"));

      await xWinSwapV3.swapTokenToToken(
        defaultAmount,
        bsc.USDT,
        await xBTCB.getAddress()
      );
      await xWinSwapV3.swapTokenToToken(
        defaultAmount,
        bsc.USDT,
        await xWinDCA.getAddress()
      );

      const balancexBTC = await xBTCB.balanceOf(await owner.getAddress());
      const balancexWinDCA = await xWinDCA.balanceOf(await owner.getAddress());

      expectAlmostEquals(balancexBTC, ethers.parseEther("0.02335"));
      expectAlmostEquals(balancexWinDCA, ethers.parseEther("1000"));

      await xWinSwapV3.swapTokenToToken(
        ethers.parseEther("0.1"),
        bsc.BTCB,
        await xBTCB.getAddress()
      );
      await xWinSwapV3.swapTokenToToken(
        ethers.parseEther("0.1"),
        bsc.BTCB,
        await xWinDCA.getAddress()
      );

      expectAlmostEquals(
        (await xBTCB.balanceOf(await owner.getAddress())) - balancexBTC,
        ethers.parseEther("0.1")
      );
      expectAlmostEquals(
        (await xWinDCA.balanceOf(await owner.getAddress())) - balancexWinDCA,
        ethers.parseEther("4250")
      );
    });
  });
});
