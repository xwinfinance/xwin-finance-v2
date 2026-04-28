const fs = require("fs");
const path = require("path");

const DEFAULTS = {
  privateKey: process.env.XWIN_PRIVATE_KEY,
  bscNode:
    process.env.BSC_NODE || "https://bsc-dataseed.binance.org/",
  ethereumNode:
    process.env.ETHEREUM_NODE || "https://eth.llamarpc.com",
  arbitrumNode:
    process.env.ARBITRUM_NODE || "https://arb1.arbitrum.io/rpc",
  polygonNode:
    process.env.POLYGON_NODE || "https://polygon-rpc.com/",
};

let cachedSecrets;

function loadSecrets() {
  if (cachedSecrets) {
    return cachedSecrets;
  }

  const secretsPath = path.join(__dirname, "secrets.json");
  let fromFile = {};

  if (fs.existsSync(secretsPath)) {
    try {
      // eslint-disable-next-line import/no-dynamic-require, global-require
      fromFile = require("./secrets.json");
    } catch (e) {
      console.warn(
        "[fork.configs] Could not read secrets.json, using defaults and env:",
        e.message
      );
    }
  } else if (!process.env.XWIN_FORCE_QUIET_FORK) {
    console.warn(
      "[fork.configs] No secrets.json found. Using public RPC defaults via env or built-ins. Fork tests need a BSC archive RPC in secrets.json or BSC_NODE."
    );
  }

  cachedSecrets = { ...DEFAULTS, ...fromFile };
  return cachedSecrets;
}

// Update hardhat forking configurations here
// Use chain=56 blockNumberBSC=35227815 for test scripts
// Or use chain 31337 for test scripts
const forkConfigs = {
  chainID: 56,
  blockNumberBSC: 77680504,
  blockNumberArb: 194252889,
  blockNumberPolygon: 59220994,
  blockNumberEth: 19515540,
};

function getForkingConfig() {
  const { bscNode, ethereumNode, arbitrumNode, polygonNode } = loadSecrets();

  if (forkConfigs.chainID === 1) {
    return {
      RPCNode: ethereumNode,
      blockNumber: forkConfigs.blockNumberEth,
    };
  }

  if (forkConfigs.chainID === 56) {
    return {
      RPCNode: bscNode,
      blockNumber: forkConfigs.blockNumberBSC,
    };
  }

  if (forkConfigs.chainID === 137) {
    return {
      RPCNode: polygonNode,
      blockNumber: forkConfigs.blockNumberPolygon,
    };
  }

  if (forkConfigs.chainID === 31337) {
    return {
      RPCNode: bscNode,
      blockNumber: 35227815,
    };
  }

  if (forkConfigs.chainID === 42161) {
    return {
      RPCNode: arbitrumNode,
      blockNumber: forkConfigs.blockNumberArb,
    };
  }

  throw new Error("fork.configs: unsupported chainID " + forkConfigs.chainID);
}

module.exports = {
  loadSecrets,
  getForkingConfig,
};
