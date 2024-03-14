// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ITWAPOracle {
    function massUpdate() external;

    function consult(
        address token0,
        address token1,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}
