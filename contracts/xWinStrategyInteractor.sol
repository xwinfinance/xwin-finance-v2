// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./xWinStrategy.sol";

contract xWinStrategyInteractor is OwnableUpgradeable, PausableUpgradeable {

    modifier onlyAdmin {
        require(
            admins[msg.sender],
            "Only admin can call this function."
        );
        _;
    }

    struct StrategyData {
        address baseToken;
        bool isActive;
    }

    mapping(address => bool) public admins;
    mapping(address => StrategyData) public xWinStrategies;
    uint256[10] private __gap;
    function __xWinStrategyInteractor_init() onlyInitializing internal {
        __Ownable_init();
        __Pausable_init();
        admins[msg.sender] = true;
    }

    // Support multiple wallets or address as admin
    function setAdmin(address _wallet, bool _allow) external onlyOwner {
        admins[_wallet] = _allow;
    }

    function isAdmin(address _wallet) public view returns (bool)  {
        return admins[_wallet];
    }

    // registers and activates a strat
    function registerStrategyContract(address _newStrat, address _baseToken) external onlyAdmin {
        require(_baseToken != address(0), "_baseToken input is 0");
        StrategyData memory data;
        data.baseToken = _baseToken;
        data.isActive = true;
        xWinStrategies[_newStrat] = data;
    }

    //activate a deactivated strat
    function activateStrategy(address _strat) public onlyAdmin {
        require(isxWinStrategy(_strat), "xWinStrategy: not strategy contract");
        xWinStrategies[_strat].isActive = true;
    }

    // deactivate a dead strat
    function deactivateStrategy(address _strat) public onlyAdmin {
        require(isxWinStrategy(_strat), "xWinStrategy: not strategy contract");
        xWinStrategies[_strat].isActive = false;
    }

    function isxWinStrategy(address _strat) public view returns (bool) {
        return xWinStrategies[_strat].baseToken != address(0);
    }

    function isActivexWinStrategy(address _strat) public view returns (bool) {
        return xWinStrategies[_strat].isActive;
    }
    
    function getStrategyBaseToken(address _strat) public view returns (address) {
        return xWinStrategies[_strat].baseToken;
    }


    function depositToStrategy(uint256 _amount, address _strat) internal returns (uint256) {
        require(isxWinStrategy(_strat), "xWinStrategy: not strategy contract");
        require(isActivexWinStrategy(_strat), "xWinStrategy: it not xwin strategy");
        return xWinStrategy(_strat).deposit(_amount);
    }

    function withdrawFromStrategy(uint256 _amount, address _strat) internal returns (uint256) {
        require(isxWinStrategy(_strat), "xWinStrategy: not strategy contract");
        return xWinStrategy(_strat).withdraw(_amount);
    }

}