// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IxWinPriceMaster {
    function getPrice(
        address _from,
        address _to
    ) external view returns (uint rate);
}
