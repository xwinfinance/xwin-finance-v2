const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { xWinFixture } = require("./xWinFixture");
const { expectAlmostEquals } = require("./xWinTestHelpers.js");
const { polygon } = require("./polygonMainnetAddresses.js");
const { ethers } = require("hardhat");
const defaultAmount = ethers.parseUnits("1000", 6);

describe("Fund V2", function () {
  describe("Core", function () {
    it("Deposit", async function () {
      const { owner, accounts, fundV2Default1, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [polygon.WBTC, polygon.LINK, polygon.UNI],
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
        ethers.parseEther("1000")
      );

      await USDC.connect(accounts[0]).approve(
        await fundV2Default1.getAddress(),
        defaultAmount
      );
      await fundV2Default1.connect(accounts[0]).deposit(defaultAmount);

      expectAlmostEquals(
        await fundV2Default1.balanceOf(await owner.getAddress()),
        ethers.parseEther("10")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await accounts[0].getAddress()),
        ethers.parseEther("10")
      );
      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("100")
      );
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("2000")
      );
    });

    it("Rebalance", async function () {
      const { fundV2Default1, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [polygon.WBTC, polygon.LINK, polygon.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await fundV2Default1.Rebalance([polygon.LINK, polygon.UNI], [5000, 5000]);
      expectAlmostEquals(
        await fundV2Default1.getVaultValues(),
        ethers.parseEther("1000")
      );
    });

    it("Withdraw", async function () {
      const { accounts, fundV2Default1, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames([polygon.LINK, polygon.UNI], [5000, 5000]);
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
        ethers.parseEther("1000")
      );
    });
  });

  describe("Fees", function () {
    it("Management Fee", async function () {
      const { accounts, fundV2Default1, USDC } =
        await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [polygon.WBTC, polygon.LINK, polygon.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(ethers.Typed.uint256(defaultAmount));
      await network.provider.send("hardhat_mine", ["0xA01F36"]);

      await fundV2Default1.collectFundFee();
      await fundV2Default1.collectPlatformFee();

      expectAlmostEquals(
        await fundV2Default1.getUnitPrice(),
        ethers.parseEther("98.5")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(await accounts[1].getAddress()),
        ethers.parseEther("0.100")
      );
      expectAlmostEquals(
        await fundV2Default1.balanceOf(polygon.PlatformAddress),
        ethers.parseEther("0.0501")
      );
    });

    it("Performance Fee", async function () {
      const { owner, accounts, fundV2Default1, USDC } =
        await loadFixture(xWinFixture);
      await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [polygon.WBTC, polygon.LINK, polygon.UNI],
        [3000, 3300, 3700]
      );
      await USDC.approve(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.deposit(defaultAmount);
      await USDC.transfer(await fundV2Default1.getAddress(), defaultAmount);
      await fundV2Default1.withdraw(
        await fundV2Default1.balanceOf(await owner.getAddress())
      );

      expectAlmostEquals(
        await USDC.balanceOf(await accounts[1].getAddress()),
        ethers.parseUnits("198.9", 6)
      );
    });
  });

  describe("Misc", function () {
    it("Strategy Tokens", async function () {
      const {
        owner,
        accounts,
        fundV2Default1,
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
        USDC,
      } = await loadFixture(xWinFixture);
      await fundV2Default1.createTargetNames(
        [polygon.WBTC, polygon.USDC],
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
        [polygon.WBTC, polygon.LINK, polygon.USDC],
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
