pragma solidity ^0.8.0;
// SPDX-License-Identifier: GPL-3.0-or-later

interface IxWinTradingInterface {

    function systemReTrade() external;
    function isReTrade() external view returns (bool);
        
}