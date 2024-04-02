// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IToppyStaking {
    function nftScores(address, uint256) external view returns (uint256);
}
