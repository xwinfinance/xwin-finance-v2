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

describe("Fund V2", function () {
  describe("Core", function () {
    it("Deposit", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDT, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [arb.WBTC, arb.LINK, arb.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(
        ethers.Typed.uint256(defaultAmount),
        ethers.Typed.uint32(300)
      );

      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("1010")
      );

      await USDC.connect(accounts[0]).approve(
        await fundV2Default1.getAddress(),
        defaultAmount
      );
      await fundV2Default1.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(
        await fundV2Default1.balanceOf(await owner.getAddress()),
        ethers.parseEther("10.1")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await accounts[0].getAddress()),
        ethers.parseEther("10.1")
      );
      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("2020")
      );
    });

    it("Rebalance", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [arb.WBTC, arb.LINK, arb.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await fundV2Default1.Rebalance([arb.LINK, arb.UNI], [5000, 5000]);
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("1020")
      );
    });

    it("Withdraw", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames([arb.LINK, arb.UNI], [5000, 5000]);
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await fundV2Default1.getAddress(),
        defaultAmount
      );
      await fundV2Default1.connect(accounts[0]).deposit(defaultAmount);

      await fundV2Default1
        .connect(accounts[0])
        .withdraw(
          await fundV2Default1.balanceOf(await accounts[0].getAddress())
        );

      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("1020")
      );
    });
  });

  describe("Fees", function () {
    it("Management Fee", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [arb.WBTC, arb.LINK, arb.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await network.provider.send("hardhat_mine", ["0xA01F36"]);

      await fundV2Default1.collectFundFee();
      await fundV2Default1.collectPlatformFee();

      // console.log(await fundV2Default1.getUnitPrice(), "await fundV2Default1.getUnitPrice()")
      // console.log(await fundV2Default1.balanceOf(await accounts[1].getAddress()), "fundV2Default1.balanceOf(await accounts[1].getAddress())")
      // console.log(await fundV2Default1.balanceOf(arb.PlatformAddress), "fundV2Default1.balanceOf(arb.PlatformAddress)")

      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("98.5")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await accounts[1].getAddress()),
        ethers.parseEther("0.102")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(arb.PlatformAddress),
        ethers.parseEther("0.0507")
      );
    });

    it("Performance Fee", async function () {
      const { owner, accounts, fundV2Default1, fundV2Default2, USDC } =
        await loadFixture(xWinFixture);
      await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [arb.WBTC, arb.LINK, arb.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await USDC.transfer(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );
      // console.log(await USDC.balanceOf(await accounts[1].getAddress()), "await USDC.balanceOf(await accounts[1].getAddress())")

      expectAlmostEquals(
        await USDC.balanceOf(await accounts[1].getAddress()),
        ethers.parseUnits("197", 6)
      );
    });
  });

  describe("Misc", function () {
    it("Strategy Tokens", async function () {
      const {
        owner,
        accounts,
        fundV2Default1,
        fundV2Default2,
        xWinDCA,
        xWinTokenAlpha,
        xWBTC,
        USDC,
      } = await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [
          await xWinDCA.getAddress(),
          await xWinTokenAlpha.getAddress(),
          await xWBTC.getAddress(),
        ],
        [3400, 3300, 3300]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await fundV2Default1.getAddress(),
        defaultAmount
      );
      await fundV2Default1.connect(accounts[0]).deposit(defaultAmount);
      await fundV2Default1.Rebalance(
        [
          await xWinDCA.getAddress(),
          await xWinTokenAlpha.getAddress(),
          await xWBTC.getAddress(),
        ],
        [3700, 3000, 3300]
      );
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );
      await fundV2Default1
        .connect(accounts[0])
        .withdraw(
          await fundV2Default1.balanceOf(await accounts[0].getAddress())
        );
    });

    it("Contains Base Token", async function () {
      const {
        owner,
        accounts,
        fundV2Default1,
        fundV2Default2,
        xWinDCA,
        xWinTokenAlpha,
        xWBTC,
        USDC,
      } = await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [arb.WBTC, arb.USDC],
        [5000, 5000]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await USDC.connect(accounts[0]).approve(
        await fundV2Default1.getAddress(),
        defaultAmount
      );
      await fundV2Default1.connect(accounts[0]).deposit(defaultAmount);
      await fundV2Default1.Rebalance(
        [arb.WBTC, arb.LINK, arb.USDC],
        [2500, 5000, 2500]
      );
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );
      await fundV2Default1
        .connect(accounts[0])
        .withdraw(
          await fundV2Default1.balanceOf(await accounts[0].getAddress())
        );
    });
  });
});
