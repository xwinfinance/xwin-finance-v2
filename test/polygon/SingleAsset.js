const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { polygon } = require("./polygonMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseUnits("100", 6);
const defaultAmountBTC = ethers.parseUnits("0.01", 8);

describe("Single Asset", function () {
  describe("Core", function () {
    it("xUSDC", async function () {
      const { owner, accounts, USDT, xUSDT } = await loadFixture(
        xWinFixture
      );
      await USDT.approve(await xUSDT.getAddress(), defaultAmount);
      await USDT.connect(accounts[0]).approve(
        await xUSDT.getAddress(),
        defaultAmount
      );

      await xUSDT.deposit(defaultAmount);

      expect(await xUSDT.baseToken()).to.equal(polygon.USDT);
      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xUSDT.getVaultValues(), ethers.parseEther("100"));
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("100")
      );

      await xUSDT.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(await xUSDT.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xUSDT.getVaultValues(),
        ethers.parseEther("200")
      );
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("200")
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
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await xUSDT.getVaultValuesInUSD(),
        ethers.parseEther("100")
      );
    });

    it("xWBTC", async function () {
      const { owner, accounts, xWBTC, WBTC } = await loadFixture(
        xWinFixture
      );
      await WBTC.approve(await xWBTC.getAddress(), defaultAmountBTC);
      await WBTC.connect(accounts[0]).approve(
        await xWBTC.getAddress(),
        defaultAmountBTC
      );

      expect(await xWBTC.baseToken()).to.equal(polygon.WBTC);
      
      await xWBTC.deposit(defaultAmountBTC);

      expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xWBTC.getVaultValues(), ethers.parseEther("0.01"));
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("701.1")
      );

      await xWBTC.connect(accounts[0]).deposit(defaultAmountBTC);

      expectAlmostEquals(await xWBTC.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWBTC.getVaultValues(),
        ethers.parseEther("0.02")
      );
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("1402.2")
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
        ethers.parseEther("0.01")
      );
      expectAlmostEquals(
        await xWBTC.getVaultValuesInUSD(),
        ethers.parseEther("701.1")
      );
    });
  });
});
