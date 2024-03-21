const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { bsc, hardhatNode } = require("../bscMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseEther("1000");
describe("Fund V2", function () {
  describe("Core", function () {
    it("Deposit", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(
        ethers.Typed.uint256(defaultAmount),
        ethers.Typed.uint32(300)
      );
      expectAlmostEquals(await fundV2Default1.getUnitPrice(), ethers.parseEther('100'));
      expectAlmostEquals(await fundV2Default1.getVaultValues(), ethers.parseEther('1000'));

      await USDT.connect(accounts[0]).approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.connect(accounts[0]).deposit(
        defaultAmount
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await owner.getAddress()),
        (defaultAmount - defaultAmount / BigInt(100)) / BigInt(100)
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await accounts[0].getAddress()),
        (defaultAmount - defaultAmount / BigInt(100)) / BigInt(100)
      );
      expectAlmostEquals(await fundV2Default1.getUnitPrice(), ethers.parseEther('100'));
      expectAlmostEquals(await fundV2Default1.getVaultValues(), ethers.parseEther('2000'));
    });

    it("Rebalance", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await fundV2Default1.Rebalance(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3700, 3000, 3300],
      );
      expectAlmostEquals(await fundV2Default1.getVaultValues(), ethers.parseEther('1000'));
    });

    it("Withdraw", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await USDT.connect(accounts[0]).approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.connect(accounts[0]).deposit(
        defaultAmount
      );
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );

      expectAlmostEquals(await fundV2Default1.getUnitPrice(), ethers.parseEther('100'));
      expectAlmostEquals(await fundV2Default1.getVaultValues(), ethers.parseEther('1000'));

      await fundV2Default1.connect(accounts[0]).withdraw(
        await fundV2Default1.balanceOf(await accounts[0].getAddress())
      );
    });
  });

  describe("Fees", function () {
    it("Management Fee", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await network.provider.send("hardhat_mine", ["0xA01F36"]);

      await fundV2Default1.collectFundFee();
      await fundV2Default1.collectPlatformFee();

    });

    it("Performance Fee", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT } =
        await loadFixture(xWinFixture);
      await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [bsc.BTCB, bsc.ETH, bsc.WBNB],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await USDT.transfer(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );
    });
  });

  describe("Misc", function () {
    it("Strategy Tokens", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, xWinDCA, xWinTokenAlpha, xBTCB, USDT } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [await xWinDCA.getAddress(), await xWinTokenAlpha.getAddress(), await xBTCB.getAddress()],
        [3000, 3300, 3700]
      );
      await USDT.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await USDT.connect(accounts[0]).approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.connect(accounts[0]).deposit(
        defaultAmount
      );
      await fundV2Default1.Rebalance(
        [await xWinDCA.getAddress(), await xWinTokenAlpha.getAddress(), await xBTCB.getAddress()],
        [3700, 3000, 3300],
      );
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );
      await fundV2Default1.connect(accounts[0]).withdraw(
        await fundV2Default1.balanceOf(await accounts[0].getAddress())
      );
    });
  });
});
