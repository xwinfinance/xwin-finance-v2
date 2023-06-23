// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IxWinStrategyInteractor {
    function registerStrategyContract(address _newStrat, address _baseToken) external;
    function activateStrategy(address _strat) external;
    function deactivateStrategy(address _strat) external;
    function isxWinStrategy(address _strat) external view returns (bool);
    function isActivexWinStrategy(address _strat) external view returns (bool);
    function depositToStrategy(uint256 _amount, address _strat) external payable returns(uint256);
    function withdrawFromStrategy( uint256 _amount, address _strat) external returns(uint256);
    function getStrategyBaseToken(address _strat) external view returns (address);
    function setAdmin(address _wallet, bool _allow) external;
    function isAdmin(address _wallet) external view returns (bool);
}