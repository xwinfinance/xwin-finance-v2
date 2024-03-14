// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IxWinSingleAssetInterface {

    function deposit(uint _amount) external returns (uint256);
    function withdraw(uint _amount) external returns (uint256);
    function deposit(uint256 amount, uint32 slippage) external returns (uint256);
    function withdraw(uint256 amount, uint32 slippage) external returns (uint256);
    function getUnitPrice()  external view returns (uint256);
    function getUnitPriceInUSD()  external view returns (uint256);
    function getUserBalance(address _user)  external view returns (uint256);
    function getVaultValuesInUSD() external view returns (uint);
    function getVaultValues() external view returns (uint vaultValue);
    function getSupplyRatePerBlock() external view returns (uint);
    function getBorrowRatePerBlock() external view returns (uint);
    function canSystemDeposit() external view returns (bool);
    function systemDeposit() external;
    function canReclaimRainMaker() external view returns (bool);
    function reinvestClaimComp() external;
}
