// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

interface IWBETH {

    function exchangeRate() external view returns (uint256);
    function deposit(uint256 amount, address referral) external;
}