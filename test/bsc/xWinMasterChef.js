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

describe("xWinMasterChef", function () {
  describe("Core", function () {
    it("Add pools", async function () {
      const { owner, accounts, xWinMasterChef, xWinToken } = await loadFixture(
        xWinFixture
      );

      // 2. add USDT & WBNB pool
      await xWinMasterChef.add(500, bsc.USDT, "365"); //pool 2
      await xWinMasterChef.add(500, bsc.BTCB, "365"); //pool 3

      expect((await xWinMasterChef.poolInfo(2)).allocPoint).to.equal(500);
      expect((await xWinMasterChef.poolInfo(3)).allocPoint).to.equal(500);
    });

    it("Deposit", async function () {
      const { owner, accounts, xWinMasterChef, USDT, xWinToken } =
        await loadFixture(xWinFixture);

      await xWinMasterChef.add(500, bsc.USDT, "365"); //pool 2
      await xWinMasterChef.add(500, bsc.BTCB, "365"); //pool 3

      await xWinToken.approve(await xWinMasterChef.getAddress(), defaultAmount);
      await USDT.approve(
        await xWinMasterChef.getAddress(),
        ethers.parseEther("100")
      );

      await xWinMasterChef.deposit(0, defaultAmount);
      await xWinMasterChef.deposit(2, ethers.parseEther("100"));

      expect(
        (await xWinMasterChef.userInfo(0, hardhatNode.publicAddress)).amount
      ).to.equal(defaultAmount);
      expect(
        (await xWinMasterChef.userInfo(2, hardhatNode.publicAddress)).amount
      ).to.equal(ethers.parseEther("100"));
    });

    it("Harvest Withdraw", async function () {
      const { owner, accounts, xWinMasterChef, USDT, xWinToken } =
        await loadFixture(xWinFixture);

      await xWinMasterChef.add(500, bsc.USDT, "365"); //pool 2
      await xWinMasterChef.add(500, bsc.BTCB, "365"); //pool 3

      await xWinToken.approve(await xWinMasterChef.getAddress(), defaultAmount);
      await USDT.approve(
        await xWinMasterChef.getAddress(),
        ethers.parseEther("100")
      );

      await xWinMasterChef.deposit(0, defaultAmount);
      await xWinMasterChef.deposit(2, ethers.parseEther("100"));

      await network.provider.send("hardhat_mine", ["0x4B0"]);
      expectAlmostEquals(
        await xWinMasterChef.pendingRewards(0, hardhatNode.publicAddress),
        ethers.parseEther("3.80")
      );
      expectAlmostEquals(
        await xWinMasterChef.pendingRewards(2, hardhatNode.publicAddress),
        ethers.parseEther("1.90")
      );

      // harvest
      await xWinMasterChef.deposit(0, 0);
      await xWinMasterChef.deposit(2, 0);

      expect(
        await xWinMasterChef.pendingRewards(0, hardhatNode.publicAddress)
      ).to.be.lessThan(ethers.parseEther("0.01"));
      expect(
        await xWinMasterChef.pendingRewards(2, hardhatNode.publicAddress)
      ).to.be.lessThan(ethers.parseEther("0.01"));

      const xWinBalance = await xWinToken.balanceOf(hardhatNode.publicAddress);
      const USDTBalance = await USDT.balanceOf(hardhatNode.publicAddress);

      await xWinMasterChef.withdraw(0, defaultAmount);
      await xWinMasterChef.withdraw(2, ethers.parseEther("100"));

      expectAlmostEquals(
        (await xWinToken.balanceOf(hardhatNode.publicAddress)) - xWinBalance,
        defaultAmount
      );
      expectAlmostEquals(
        (await USDT.balanceOf(hardhatNode.publicAddress)) - USDTBalance,
        ethers.parseEther("100")
      );
    });
  });
});
