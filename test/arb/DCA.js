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

describe("DCA", function () {
  describe("Core", function () {
    it("xUSDC-xBTC", async function () {
      const { owner, accounts, xWinDCA, USDC } = await loadFixture(xWinFixture);
      await USDC.approve(await xWinDCA.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinDCA.getAddress(),
        defaultAmount
      );

      expect(await xWinDCA.baseToken()).to.equal(arb.USDC);

      await xWinDCA.deposit(defaultAmount);

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("1000")
      );

      //test before one day passed
      await expect(xWinDCA.systemDeposit()).to.be.revertedWith(
        "wait till next reinvest cycle"
      );

      //fastfrwd one day
      await network.provider.send("hardhat_mine", ["0x7080"]);
      let canSystemDeposit = await xWinDCA.canSystemDeposit();
      expect(canSystemDeposit).to.equal(true);
      // not executor test
      await expect(
        xWinDCA.connect(accounts[1]).systemDeposit()
      ).to.be.revertedWith("executor: wut?");

      await xWinDCA.systemDeposit();
      // expect(canSystemDeposit).to.equal(false);

      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("988")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseUnits("10.8", 6)
      );
      expectAlmostEquals(await xWinDCA.getBaseValues(), ethers.parseEther("0"));

      await xWinDCA.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("2000")
      );

      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinDCA.systemDeposit();

      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("1966")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseUnits("32", 6)
      );
      expectAlmostEquals(await xWinDCA.getBaseValues(), ethers.parseEther("0"));

      await xWinDCA.withdraw(await xWinDCA.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("1000")
      );
    });
  });
});
