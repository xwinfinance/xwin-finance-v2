// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface xWinDefiInterface {
    
    function getPlatformFee() view external returns (uint256);
    function getPlatformAddress() view external returns (address);
    function gexWinBenefitPool() view external returns (address) ;
}