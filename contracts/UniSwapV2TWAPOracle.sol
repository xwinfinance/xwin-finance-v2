// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.6;
pragma experimental ABIEncoderV2;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

contract UniSwapV2TWAPOracle {
    using FixedPoint for *;

    struct twapData {
        IUniswapV2Pair pair; // contract addr to price pair
        address token0;
        address token1;
        uint256 price0CummulativeLast;
        uint256 price1CummulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }
    address public owner;
    address public WBNB;
    uint256 public lastUpdate;
    uint32 public period = 7200; // min seconds between each updates
    twapData[] public twapRegistry;
    mapping(address => mapping(address => uint256)) public twapIndex;
    mapping(address => bool) public executors;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address _WBNB) public {
        require(_WBNB != address(0), "Input address 0");
        owner = msg.sender;
        // push empty twapData into index 0
        twapData memory _newTWAP;
        twapRegistry.push(_newTWAP);
        lastUpdate = block.timestamp;
        WBNB = _WBNB;
        executors[msg.sender] = true;
    }

    function addPair(address pairAddr) external onlyExecutor {
        twapData memory _newTWAP;
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        _newTWAP.pair = pair;
        _newTWAP.token0 = pair.token0();
        _newTWAP.token1 = pair.token1();
        _newTWAP.price0CummulativeLast = pair.price0CumulativeLast();
        _newTWAP.price1CummulativeLast = pair.price1CumulativeLast();
        (, , _newTWAP.blockTimestampLast) = pair.getReserves();
        twapIndex[_newTWAP.token0][_newTWAP.token1] = twapRegistry.length;
        twapRegistry.push(_newTWAP);
    }

    function massUpdate() public onlyExecutor {
        for (uint256 i = 1; i < twapRegistry.length; i++) {
            uint256 price0Cummulative;
            uint256 price1Cummulative;
            uint32 blockTimestamp;
            (
                price0Cummulative,
                price1Cummulative,
                blockTimestamp
            ) = UniswapV2OracleLibrary.currentCumulativePrices(
                address(twapRegistry[i].pair)
            );
            uint32 timeElapsed = blockTimestamp -
                twapRegistry[i].blockTimestampLast;

            // skip TWAP if timeElapsed too low
            if (timeElapsed < period) {
                continue;
            }

            twapRegistry[i].price0Average = FixedPoint.uq112x112(
                uint224(
                    (price0Cummulative -
                        twapRegistry[i].price0CummulativeLast) / timeElapsed
                )
            );
            twapRegistry[i].price1Average = FixedPoint.uq112x112(
                uint224(
                    (price1Cummulative -
                        twapRegistry[i].price1CummulativeLast) / timeElapsed
                )
            );

            twapRegistry[i].price0CummulativeLast = price0Cummulative;
            twapRegistry[i].price1CummulativeLast = price1Cummulative;
            twapRegistry[i].blockTimestampLast = blockTimestamp;
        }
        lastUpdate = block.timestamp;
    }

    function consult(
        address token0,
        address token1,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        uint256 index = twapIndex[token0][token1];
        if (index == 0) {
            index = twapIndex[token1][token0];
        }
        if (index != 0) {
            // simple case direct price read
            FixedPoint.uq112x112 memory price0 = twapRegistry[index]
                .price0Average;
            FixedPoint.uq112x112 memory price1 = twapRegistry[index]
                .price1Average;
            if (token0 == twapRegistry[index].token0) {
                amountOut = price0.mul(amountIn).decode144();
            } else {
                amountOut = price1.mul(amountIn).decode144();
            }
        } else {
            // direct pair not found, will attempt token0 - WBNB - token1 path
            index = twapIndex[token0][WBNB];
            uint256 index2 = twapIndex[token1][WBNB];
            if (index == 0) {
                index = twapIndex[WBNB][token0];
            }
            if (index2 == 0) {
                index2 = twapIndex[WBNB][token1];
            }

            // pair route not found
            if (index == 0 || index2 == 0) {
                return 0;
            }

            FixedPoint.uq112x112 memory pair0Price0 = twapRegistry[index]
                .price0Average;
            FixedPoint.uq112x112 memory pair0Price1 = twapRegistry[index]
                .price1Average;
            FixedPoint.uq112x112 memory pair1Price0 = twapRegistry[index2]
                .price0Average;
            FixedPoint.uq112x112 memory pair1Price1 = twapRegistry[index2]
                .price1Average;
            if (token0 == twapRegistry[index].token0) {
                if (token1 == twapRegistry[index2].token0) {
                    // token0 - WBNB && token1 - WBNB
                    amountOut = pair1Price1
                        .mul(pair0Price0.mul(amountIn).decode144())
                        .decode144();
                } else {
                    // token0 - WBNB && WBNB - token1
                    amountOut = pair1Price0
                        .mul(pair0Price0.mul(amountIn).decode144())
                        .decode144();
                }
            } else {
                if (token1 == twapRegistry[index2].token0) {
                    // WBNB - token0 && token1 - WBNB
                    amountOut = pair1Price1
                        .mul(pair0Price1.mul(amountIn).decode144())
                        .decode144();
                } else {
                    // WBNB - token0 && WBNB - token1
                    amountOut = pair1Price0
                        .mul(pair0Price1.mul(amountIn).decode144())
                        .decode144();
                }
            }
        }
    }

    function setPeriod(uint32 _period) external onlyExecutor {
        period = _period;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller not owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function setExecutor(address _address, bool _allow) external onlyOwner {
        executors[_address] = _allow;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }
}
