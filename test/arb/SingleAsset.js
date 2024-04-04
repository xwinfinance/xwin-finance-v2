const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { bsc, hardhatNode } = require("./arbMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseEther("1000");
const defaultAmountBTC = ethers.parseEther("0.1");

describe("Single Asset", function () {
  describe("Core", function () {
    it("xUSDC", async function () {
      const { owner, accounts, xUSDC, xWBTC, USDT, xUSDT } = await loadFixture(
        xWinFixture
      );
      await USDT.approve(await xUSDT.getAddress(), defaultAmount);
      await USDT.connect(accounts[0]).approve(
        await xUSDT.getAddress(),
        defaultAmount
      );

      expect(await xUSDT.baseToken()).to.equal(arb.USDT);
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

    // it("xWBTC", async function () {
    //   const { owner, accounts, xUSDT, xWBTC, USDT, WBTC } = await loadFixture(
    //     xWinFixture
    //   );
    //   await WBTC.approve(await xWBTC.getAddress(), defaultAmountBTC);
    //   await WBTC.connect(accounts[0]).approve(
    //     await xWBTC.getAddress(),
    //     defaultAmountBTC
    //   );

    //   expect(await xWBTC.baseToken()).to.equal(arb.BTCB);
    //   expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
    //   expectAlmostEquals(await xWBTC.getVaultValues(), ethers.parseEther("0"));
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValuesInUSD(),
    //     ethers.parseEther("0")
    //   );

    //   await xWBTC.deposit(defaultAmountBTC);

    //   expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
    //   expectAlmostEquals(await xWBTC.getVaultValues(), defaultAmountBTC);
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValuesInUSD(),
    //     ethers.parseEther("4260")
    //   );

    //   await xWBTC.connect(accounts[0]).deposit(defaultAmountBTC);

    //   expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValues(),
    //     ethers.parseEther("0.2")
    //   );
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValuesInUSD(),
    //     ethers.parseEther("8520")
    //   );

    //   await xWBTC.systemDeposit();

    //   await xWBTC.withdraw(await xWBTC.balanceOf(await owner.getAddress()));

    //   expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValues(),
    //     ethers.parseEther("0.1")
    //   );
    //   expectAlmostEquals(
    //     await xWBTC.getVaultValuesInUSD(),
    //     ethers.parseEther("4260")
    //   );
    // });
  });
});
