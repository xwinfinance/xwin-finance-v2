// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IxWinSwap {
    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken
    ) external payable returns (uint);

    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken,
        uint32 _slippage
    ) external payable returns (uint);

    function swapTokenToExactToken(
        uint _amount,
        uint _exactAmount,
        address _fromToken,
        address _toToken
    ) external payable returns (uint);

    function addTokenPath(
        address _router,
        address _fromtoken,
        address _totoken,
        address[] memory path,
        uint256 _slippage
    ) external;
}
