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
const defaultAmount = ethers.parseEther("10000");

describe("TokenAlpha", function () {
  describe("Core", function () {
    it("xUSDT-xBTC", async function () {
      const { owner, accounts, xWinTokenAlpha, xUSDT, USDT, BTCB } =
        await loadFixture(xWinFixture);
      await USDT.approve(await xWinTokenAlpha.getAddress(), defaultAmount);
      await USDT.connect(accounts[0]).approve(
        await xWinTokenAlpha.getAddress(),
        defaultAmount
      );

      expect(await xWinTokenAlpha.baseToken()).to.equal(bsc.USDT);
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
      expectAlmostEquals(await xWinTokenAlpha.getVaultValues(), defaultAmount);

      await USDT.transfer(await xUSDT.getAddress(), ethers.parseEther("100"));
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinTokenAlpha.systemDeposit();

      expectAlmostEquals(await xWinTokenAlpha.getStableValues(), defaultAmount);
      expectAlmostEquals(
        await xWinTokenAlpha.getTargetValues(),
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getBaseValues(),
        ethers.parseEther("0")
      );

      await xWinTokenAlpha.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(
        await xWinTokenAlpha.getUnitPrice(),
        ethers.parseEther("1.01")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getVaultValues(),
        ethers.parseEther("20000")
      );

      await USDT.transfer(await xUSDT.getAddress(), ethers.parseEther("200"));
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinTokenAlpha.systemDeposit();
      expectAlmostEquals(
        await xWinTokenAlpha.getStableValues(),
        ethers.parseEther("20000")
      );
      expectAlmostEquals(
        await xWinTokenAlpha.getTargetValues(),
        ethers.parseEther("300")
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
        ethers.parseEther("1.02")
      );
      expectAlmostEquals(await xWinTokenAlpha.getVaultValues(), defaultAmount);
    });
  });
});
