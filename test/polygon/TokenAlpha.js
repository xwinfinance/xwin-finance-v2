const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { polygon } = require("./polygonMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseUnits("1000", 6);

describe("TokenAlpha", function () {
  describe("Core", function () {
    it("xUSDC-xBTC - Deposit, Withdraw, SystemDeposit", async function () {
      const { owner, accounts, xWinTokenAlpha, xUSDC, USDC } =
        await loadFixture(xWinFixture);
      await USDC.approve(await xWinTokenAlpha.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinTokenAlpha.getAddress(),
        defaultAmount
      );

      expect(await xWinTokenAlpha.baseToken()).to.equal(polygon.USDC);
      expectAlmostEquals(
        await xWinTokenAlpha.getUnitPrice(),
        ethers.parseEther("1")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValuesInUSD(),
        ethers.parseEther("0")
      );

      await xWinTokenAlpha.deposit(defaultAmount);

      expectAlmostEquals(
        await xWinTokenAlpha.getUnitPrice(),
        ethers.parseEther("1")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValues(),
        ethers.parseEther("1000")
      );

      // send usdc as interest earned in this unit test 10%
      await USDC.transfer(
        await xUSDC.getAddress(),
        ethers.parseUnits("100", 6)
      );
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinTokenAlpha.systemDeposit();

      expectAlmostEquals(
        await xWinTokenAlpha.getStableValues(),
        ethers.parseEther("1000")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getTargetValues(),
        ethers.parseUnits("100", 6) // staked 100 earned into staking and buy xbtc
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getBaseValues(),
        ethers.parseEther("0")
      );

      await xWinTokenAlpha.connect(accounts[0]).deposit(defaultAmount);

      // unit price increase 10% from 1 to 1.10
      expectAlmostEquals(
        await xWinTokenAlpha.getUnitPrice(),
        ethers.parseEther("1.1")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValues(),
        ethers.parseEther("2100")
      );

      // send usdc as interest earned in this unit test
      await USDC.transfer(
        await xUSDC.getAddress(),
        ethers.parseUnits("200", 6)
      );

      //test before one day passed
      await expect(xWinTokenAlpha.systemDeposit()).to.be.revertedWith(
        "wait till next reinvest cycle"
      );

      await network.provider.send("hardhat_mine", ["0x7080"]);

      // not executor test
      await expect(
        xWinTokenAlpha.connect(accounts[1]).systemDeposit()
      ).to.be.revertedWith("executor: wut?");

      await xWinTokenAlpha.systemDeposit();
      expectAlmostEquals(
        await xWinTokenAlpha.getStableValues(),
        ethers.parseEther("2000")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getTargetValues(),
        ethers.parseUnits("300", 6)
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getBaseValues(),
        ethers.parseEther("0")
      );

      await xWinTokenAlpha.withdraw(
        await xWinTokenAlpha.balanceOf(await owner.getAddress())
      );

      expectAlmostEquals(
        await xWinTokenAlpha.getUnitPrice(),
        ethers.parseEther("1.20")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValues(),
        ethers.parseEther("1100")
      );
    });
    it("xUSDC-xBTC - Emergency Unwind / Pause / Unpause", async function () {
      const { owner, accounts, xWinTokenAlpha, xUSDC, USDC } =
        await loadFixture(xWinFixture);
      await USDC.approve(await xWinTokenAlpha.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinTokenAlpha.getAddress(),
        defaultAmount
      );
      await xWinTokenAlpha.deposit(defaultAmount);
      // send usdc as interest earned in this unit test 10%
      await USDC.transfer(
        await xUSDC.getAddress(),
        ethers.parseUnits("100", 6)
      );
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinTokenAlpha.systemDeposit();

      await expect(xWinTokenAlpha.emergencyUnWindPosition()).to.be.revertedWith(
        "Pausable: not paused"
      );

      await xWinTokenAlpha.setPause();
      await xWinTokenAlpha.emergencyUnWindPosition();

      expectAlmostEquals(
        await xWinTokenAlpha.getStableValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getTargetValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getBaseValues(),
        ethers.parseEther("1100")
      );

      await expect(
        xWinTokenAlpha.withdraw(ethers.parseEther("100"))
      ).to.be.revertedWith("Pausable: paused");

      await xWinTokenAlpha.setUnPause();

      let bal = await xWinTokenAlpha.balanceOf(owner);
      await xWinTokenAlpha.withdraw(ethers.parseEther("500")); // 50% withdraw
      expectAlmostEquals(
        await xWinTokenAlpha.getBaseValues(),
        ethers.parseEther("550")
      );
    });
    it("xUSDC-xBTC - Performance Fee", async function () {
      const { accounts, xWinTokenAlpha, xUSDC, USDC } =
        await loadFixture(xWinFixture);
      await USDC.approve(await xWinTokenAlpha.getAddress(), defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await xWinTokenAlpha.getAddress(),
        defaultAmount
      );
      await xWinTokenAlpha.deposit(defaultAmount);
      // send usdc as interest earned in this unit test 10%
      await USDC.transfer(
        await xUSDC.getAddress(),
        ethers.parseUnits("100", 6)
      );
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinTokenAlpha.systemDeposit();

      await expect(xWinTokenAlpha.collectPerformanceFee()).to.be.revertedWith(
        "block number has not passed collection block"
      );

      // fast forward 5 days for performance collection
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await network.provider.send("hardhat_mine", ["0x7080"]);

      let canCollect = await xWinTokenAlpha.canCollectPerformanceFee();
      await expect(canCollect).to.be.equal(true);

      const supplyBefore = await xWinTokenAlpha.totalSupply();
      const UPbefore = await xWinTokenAlpha.getUnitPrice();

      await xWinTokenAlpha.collectPerformanceFee();
      const supplyAfter = await xWinTokenAlpha.totalSupply();
      const UPAfter = await xWinTokenAlpha.getUnitPrice();
      expect(supplyAfter).to.be.greaterThan(supplyBefore);
      expect(UPbefore).to.be.greaterThan(UPAfter);
    });
  });
});
