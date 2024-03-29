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

describe("xWinPriceMaster", function () {
  describe("Core", function () {
    it("Get Price", async function () {
      const { owner, accounts, xWinPriceMaster } = await loadFixture(
        xWinFixture
      );
      // chainlink price
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.BTCB),
        ethers.parseUnits("23480", "gwei")
      );
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.ETH),
        ethers.parseEther("0.0003921")
      );
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.WBNB),
        ethers.parseEther("0.00331")
      );
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.XVS),
        ethers.parseEther("0.08495")
      );

      // TWAP price
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.xWinToken),
        ethers.parseEther("7.18")
      );

      // LP Token price
      expectAlmostEquals(
        await xWinPriceMaster.getPrice(bsc.USDT, bsc.XWIN_BNB_pancakeLP),
        ethers.parseEther("0.0717")
      );
    });
  });
});
