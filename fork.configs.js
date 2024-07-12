const {
  bscNode,
  ethereumNode,
  arbitrumNode,
  polygonNode,
} = require("./secrets.json");

// Update hardhat forking configurations here
// Use chain=56 blockNumberBSC=35227815 for test scripts
// Or use chain 31337 for test scripts
const forkConfigs = {
  chainID: 137,
  blockNumberBSC: 35227815,
  blockNumberArb: 194252889,
  blockNumberPolygon: 59220994,
  blockNumberEth: 19515540,
};

const getForkingConfig = () => {
  if (forkConfigs.chainID == 1) {
    return {
      RPCNode: ethereumNode,
      blockNumber: forkConfigs.blockNumberEth,
    };
  }

  if (forkConfigs.chainID == 56) {
    return {
      RPCNode: bscNode,
      blockNumber: forkConfigs.blockNumberBSC,
    };
  }

  if (forkConfigs.chainID == 137) {
    return {
      RPCNode: polygonNode,
      blockNumber: forkConfigs.blockNumberPolygon,
    };
  }

  if (forkConfigs.chainID == 31337) {
    return {
      RPCNode: bscNode,
      blockNumber: 35227815,
    };
  }

  if (forkConfigs.chainID == 42161) {
    return {
      RPCNode: arbitrumNode,
      blockNumber: forkConfigs.blockNumberArb,
    };
  }
};

module.exports = {
  getForkingConfig,
};
