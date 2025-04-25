// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface OlaFinance {
    function mint(uint mintAmount) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    // function redeemUnderlying(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function balanceOfUnderlying(address account) external returns (uint);

    function exchangeRateStored() external view returns (uint);

    function borrowRatePerBlock() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function borrow(uint256) external returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint);

    function repayBorrow(uint256) external returns (uint256);
}

interface RainMakerForOlaLens {
    function claimComp(address holder) external;

    function claimVenus(address holder) external;

    function claimVenus(address holder, address[] memory vTokens) external;

    function compAccrued(address holder) external view returns (uint);

    function venusAccrued(address holder) external view returns (uint);
}

interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(
        address[] calldata
    ) external returns (uint256[] memory);

    function getAccountLiquidity(
        address
    ) external view returns (uint256, uint256, uint256);
}
