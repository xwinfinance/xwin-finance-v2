// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface xWinDefiInterface {
    function getPlatformFee() external view returns (uint256);

    function getPlatformAddress() external view returns (address);

    function gexWinBenefitPool() external view returns (address);
}
