pragma solidity ^0.8.0;
// SPDX-License-Identifier: GPL-3.0-or-later

interface IxWinStrategy {
    function getVaultValues() external view returns (uint);      
    function getVaultValuesInUSD() external view returns (uint);        
    function getUnitPrice() external view returns (uint256);
    function getUnitPriceInUSD() external view returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function deposit(uint256 amount, uint32 slippage) external returns (uint256);
    function withdraw(uint256 amount, uint32 slippage) external returns (uint256);
}