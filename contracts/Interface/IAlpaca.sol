// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAlpaca {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 share) external;

    function vaultDebtValue() external view returns (uint256);

    function totalToken() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
