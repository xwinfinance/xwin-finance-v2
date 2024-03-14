// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.9;

interface ILockedStake {
    function getFavor(address _user) external view returns (uint256);
}
