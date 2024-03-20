const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { xWinFixture } = require("./xWinFixture");

describe("Lock", function () {
  describe("Deployment", function () {
    it("Should set the right unlockTime", async function () {
      const { owner, xBTCB } = await loadFixture(xWinFixture);

      expect(await owner.getAddress()).to.equal('0');
    });
  });
});
