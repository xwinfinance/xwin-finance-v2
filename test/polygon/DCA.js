const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { polygon } = require("./polygonMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseUnits("1000", 6);

describe("DCA", function () {
  describe("Core", function () {
    it("xUSDC-xBTC - Deposit, Withdraw, SystemDeposit", async function () {
      const { owner, accounts, xWinDCA, USDC } = await loadFixture(xWinFixture);
      await USDC.approve(await xWinDCA.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinDCA.getAddress(),
        defaultAmount
      );

      expect(await xWinDCA.baseToken()).to.equal(polygon.USDC);

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

      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("988")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseUnits("11.1", 6)
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
        ethers.parseUnits("33", 6)
      );
      expectAlmostEquals(await xWinDCA.getBaseValues(), ethers.parseEther("0"));

      await xWinDCA.withdraw(await xWinDCA.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("1000")
      );
    });
    it("xUSDC-xBTC - Emergency Unwind / Pause / Unpause", async function () {
      const { accounts, xWinDCA, USDC } =
        await loadFixture(xWinFixture);
      await USDC.approve(await xWinDCA.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinDCA.getAddress(),
        defaultAmount
      );
      await xWinDCA.deposit(defaultAmount);
      // send usdc as interest earned in this unit test 10%
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinDCA.systemDeposit();
      await expect(xWinDCA.emergencyUnWindPosition()).to.be.revertedWith(
        "Pausable: not paused"
      );

      await xWinDCA.setPause();
      await xWinDCA.emergencyUnWindPosition();

      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinDCA.getBaseValues(),
        ethers.parseEther("1000")
      );

      await expect(
        xWinDCA.withdraw(ethers.parseEther("100"))
      ).to.be.revertedWith("Pausable: paused");

      await xWinDCA.setUnPause();
      await xWinDCA.withdraw(ethers.parseEther("500")); // 50% withdraw
      expectAlmostEquals(
        await xWinDCA.getBaseValues(),
        ethers.parseEther("500")
      );
    });
    it("xUSDC-xBTC - Performance Fee", async function () {
      const { accounts, xWinDCA, xUSDC, USDC, BTCB } =
        await loadFixture(xWinFixture);
      await USDC.approve(await xWinDCA.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinDCA.getAddress(),
        defaultAmount
      );
      await xWinDCA.deposit(defaultAmount);
      // send usdc as interest earned in this unit test 10%
      await USDC.transfer(
        await xUSDC.getAddress(),
        ethers.parseUnits("100", 6)
      );
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinDCA.systemDeposit();

      await expect(xWinDCA.collectPerformanceFee()).to.be.revertedWith(
        "block number has not passed collection block"
      );

      // fast forward 5 days for performance collection
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);

      let canCollect = await xWinDCA.canCollectPerformanceFee();
      await expect(canCollect).to.be.equal(true);

      const supplyBefore = await xWinDCA.totalSupply();
      const UPbefore = await xWinDCA.getUnitPrice();

      await xWinDCA.collectPerformanceFee();
      const supplyAfter = await xWinDCA.totalSupply();
      const UPAfter = await xWinDCA.getUnitPrice();
      expect(supplyAfter).to.be.greaterThan(supplyBefore);
      expect(UPbefore).to.be.greaterThan(UPAfter);
    });
  });
});
