const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { arb, hardhatNode } = require("./arbMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseUnits("1000", 6);
const defaultAmountBTC = ethers.parseUnits("0.1", 8);

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

      await xUSDT.deposit(defaultAmount);

      expect(await xUSDT.baseToken()).to.equal(arb.USDT);
      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xUSDT.getVaultValues(), ethers.parseEther("1000"));
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

      let canSystemDeposit = await xUSDT.canSystemDeposit();
      expect(canSystemDeposit).to.equal(true);
      await xUSDT.systemDeposit();
      canSystemDeposit = await xUSDT.canSystemDeposit();
      expect(canSystemDeposit).to.equal(false);
      
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

    it("xWBTC", async function () {
      const { owner, accounts, xUSDT, xWBTC, USDT, WBTC } = await loadFixture(
        xWinFixture
      );
      await WBTC.approve(await xWBTC.getAddress(), defaultAmountBTC);
      await WBTC.connect(accounts[0]).approve(
        await xWBTC.getAddress(),
        defaultAmountBTC
      );

      expect(await xWBTC.baseToken()).to.equal(arb.WBTC);
      
      await xWBTC.deposit(defaultAmountBTC);

      expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xWBTC.getVaultValues(), ethers.parseEther("0.1"));
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("7011")
      );

      await xWBTC.connect(accounts[0]).deposit(defaultAmountBTC);

      expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWBTC.getVaultValues(),
        ethers.parseEther("0.2")
      );
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("14022")
      );

      let canSystemDeposit = await xWBTC.canSystemDeposit();
      expect(canSystemDeposit).to.equal(true);
      await xWBTC.systemDeposit();
      canSystemDeposit = await xWBTC.canSystemDeposit();
      expect(canSystemDeposit).to.equal(false);
      
      await xWBTC.withdraw(await xWBTC.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWBTC.getVaultValues(),
        ethers.parseEther("0.1")
      );
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("7011")
      );
    });
  });
});
