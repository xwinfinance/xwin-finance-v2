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
const defaultAmountBTC = ethers.parseEther("0.1");

describe("Single Asset", function () {
  describe("Core", function () {
    it("xUSDT", async function () {
      const { owner, accounts, xUSDT, xBTCB, USDT, BTCB } = await loadFixture(
        xWinFixture
      );
      await USDT.approve(await xUSDT.getAddress(), defaultAmount);
      await USDT.connect(accounts[0]).approve(
        await xUSDT.getAddress(),
        defaultAmount
      );

      expect(await xUSDT.baseToken()).to.equal(bsc.USDT);
      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xUSDT.getVaultValues(), ethers.parseEther("0"));
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("0")
      );

      await xUSDT.deposit(defaultAmount);

      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xUSDT.getVaultValues(),
        ethers.parseEther("1000")
      );
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("1000")
      );

      await xUSDT.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xUSDT.getVaultValues(),
        ethers.parseEther("2000")
      );
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("2000")
      );

      await xUSDT.systemDeposit();

      await xUSDT.withdraw(await xUSDT.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xUSDT.getVaultValues(),
        ethers.parseEther("1000")
      );
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("1000")
      );
    });

    it("xBTCB", async function () {
      const { owner, accounts, xUSDT, xBTCB, USDT, BTCB } = await loadFixture(
        xWinFixture
      );
      await BTCB.approve(await xBTCB.getAddress(), defaultAmountBTC);
      await BTCB.connect(accounts[0]).approve(
        await xBTCB.getAddress(),
        defaultAmountBTC
      );

      expect(await xBTCB.baseToken()).to.equal(bsc.BTCB);
      expectAlmostEquals(await xBTCB.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xBTCB.getVaultValues(), ethers.parseEther("0"));
      expectAlmostEquals(
        await xBTCB.getVaultValuesInUSD(),
        ethers.parseEther("0")
      );

      await xBTCB.deposit(defaultAmountBTC);

      expectAlmostEquals(await xBTCB.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xBTCB.getVaultValues(), defaultAmountBTC);
      expectAlmostEquals(
        await xBTCB.getVaultValuesInUSD(),
        ethers.parseEther("4260")
      );

      await xBTCB.connect(accounts[0]).deposit(defaultAmountBTC);

      expectAlmostEquals(await xBTCB.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xBTCB.getVaultValues(),
        ethers.parseEther("0.2")
      );
      expectAlmostEquals(
        await xBTCB.getVaultValuesInUSD(),
        ethers.parseEther("8520")
      );

      await xBTCB.systemDeposit();

      await xBTCB.withdraw(await xBTCB.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xBTCB.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xBTCB.getVaultValues(),
        ethers.parseEther("0.1")
      );
      expectAlmostEquals(
        await xBTCB.getVaultValuesInUSD(),
        ethers.parseEther("4260")
      );
    });
  });
});
