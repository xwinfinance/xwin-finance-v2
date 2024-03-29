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

describe("xWinLockedStaking", function () {
  describe("Core", function () {
    it("Deposit", async function () {
      const { owner, accounts, xWinLockStaking, xWinToken } = await loadFixture(
        xWinFixture
      );
      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinLockStaking.deposit(defaultAmount, 12);
      const rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      expectAlmostEquals(rewards.xwinAmount, defaultAmount);
    });

    it("Extend & Withdraw", async function () {
      const { owner, accounts, xWinLockStaking, xWinToken } = await loadFixture(
        xWinFixture
      );
      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinLockStaking.deposit(defaultAmount, 12);

      await network.provider.send("evm_increaseTime", [7257600]);
      await network.provider.send("hardhat_mine", ["0x24EA64"]);
      let rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      expectAlmostEquals(rewards.xwinAmount, ethers.parseEther("12491"));
      expectAlmostEquals(rewards.rewardAmount, ethers.parseEther("11492"));

      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinLockStaking.deposit(defaultAmount, 12);
      rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      expectAlmostEquals(rewards.xwinAmount, ethers.parseEther("13233"));
      expectAlmostEquals(rewards.rewardAmount, ethers.parseEther("0"));

      await network.provider.send("evm_increaseTime", [7257600]);
      await network.provider.send("hardhat_mine", ["0x24EA64"]);
      rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      expectAlmostEquals(rewards.xwinAmount, ethers.parseEther("24724"));
      expectAlmostEquals(rewards.rewardAmount, ethers.parseEther("11491"));
      const xWinBalance = await xWinToken.balanceOf(hardhatNode.publicAddress);
      await xWinLockStaking.withdraw();

      expectAlmostEquals(
        (await xWinToken.balanceOf(hardhatNode.publicAddress)) - xWinBalance,
        ethers.parseEther("36216")
      );
    });

    it("Harvest", async function () {
      const { owner, accounts, xWinLockStaking, xWinToken } = await loadFixture(
        xWinFixture
      );

      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinLockStaking.deposit(defaultAmount, 12);

      await network.provider.send("hardhat_mine", ["0x14EA64"]);
      let rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      expectAlmostEquals(rewards.xwinAmount, ethers.parseEther("7510"));
      expectAlmostEquals(rewards.rewardAmount, ethers.parseEther("6511"));
      await xWinLockStaking.harvest();
      rewards = await xWinLockStaking.getUserPosition(
        hardhatNode.publicAddress
      );

      /* 
        harvest() has a fee, it compounds more xWin into masterchef, however 
        in this test case, there is no other pools in masterchef, so the 
        compounding effect is not seen
       */
      expectAlmostEquals(rewards.xwinAmount, ethers.parseEther("7364"));
      expectAlmostEquals(rewards.rewardAmount, ethers.parseEther("6511"));
    });

    it("Dry Run", async function () {
      const { owner, accounts, xWinLockStaking, xWinToken } = await loadFixture(
        xWinFixture
      );

      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinToken
        .connect(accounts[0])
        .approve(await xWinLockStaking.getAddress(), defaultAmount);
      await xWinLockStaking.deposit(defaultAmount, 12);
      await xWinLockStaking.connect(accounts[0]).deposit(defaultAmount, 16);

      await network.provider.send("evm_increaseTime", [7257600]);
      await network.provider.send("hardhat_mine", ["0x24EA64"]);

      await xWinToken.approve(
        await xWinLockStaking.getAddress(),
        defaultAmount
      );
      await xWinLockStaking.deposit(defaultAmount, 12);

      await network.provider.send("evm_increaseTime", [7257600]);
      await network.provider.send("hardhat_mine", ["0x24EA64"]);

      const xWinBalance = await xWinToken.balanceOf(hardhatNode.publicAddress);
      const xWinBalance2 = await xWinToken.balanceOf(
        hardhatNode.publicAddress2
      );

      await xWinLockStaking.withdraw();
      await xWinLockStaking.connect(accounts[0]).withdraw();

      expectAlmostEquals(
        (await xWinToken.balanceOf(hardhatNode.publicAddress)) - xWinBalance,
        ethers.parseEther("21386")
      );
      expectAlmostEquals(
        (await xWinToken.balanceOf(hardhatNode.publicAddress2)) - xWinBalance2,
        ethers.parseEther("21755")
      );
    });
  });
});
