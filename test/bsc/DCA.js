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

describe("DCA", function () {
  describe("Core", function () {
    it("xUSDT-xBTC", async function () {
      const { owner, accounts, xWinDCA, USDT, BTCB } = await loadFixture(
        xWinFixture
      );
      await USDT.approve(await xWinDCA.getAddress(), defaultAmount);
      await USDT.connect(accounts[0]).approve(
        await xWinDCA.getAddress(),
        defaultAmount
      );

      expect(await xWinDCA.baseToken()).to.equal(bsc.USDT);
      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("0")
      );
      expectAlmostEquals(
        await xWinDCA.getVaultValuesInUSD(),
        ethers.parseEther("0")
      );

      await xWinDCA.deposit(defaultAmount);

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xWinDCA.getVaultValues(), defaultAmount);
      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinDCA.systemDeposit();

      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("9970")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseEther("27.7")
      );
      expectAlmostEquals(await xWinDCA.getBaseValues(), ethers.parseEther("0"));

      await xWinDCA.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(
        await xWinDCA.getVaultValues(),
        ethers.parseEther("20000")
      );

      await network.provider.send("hardhat_mine", ["0x7080"]);
      await xWinDCA.systemDeposit();
      expectAlmostEquals(
        await xWinDCA.getStableValues(),
        ethers.parseEther("19910")
      );
      expectAlmostEquals(
        await xWinDCA.getTargetValues(),
        ethers.parseEther("83")
      );
      expectAlmostEquals(await xWinDCA.getBaseValues(), ethers.parseEther("0"));

      await xWinDCA.withdraw(await xWinDCA.balanceOf(await owner.getAddress()));

      expectAlmostEquals(await xWinDCA.getUnitPrice(), ethers.parseEther("1"));
      expectAlmostEquals(await xWinDCA.getVaultValues(), defaultAmount);
    });
  });
});
