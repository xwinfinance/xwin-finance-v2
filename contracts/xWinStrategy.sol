pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./Interface/IxWinEmitEvent.sol";


abstract contract xWinStrategy is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public stablecoinUSDAddr;
    address public baseToken; // DEPOSIT/WITHDRAW TOKEN
    IxWinEmitEvent public emitEvent;
    uint256[10] private __gap;

    function __xWinStrategy_init(
        string memory name,
        string memory symbol,
        address _baseToken,
        address _USDTokenAddr
     ) onlyInitializing internal {
        require(_baseToken != address(0), "_baseToken input 0");
        require(_USDTokenAddr != address(0), "_USDTokenAddr input 0");
        __Ownable_init();
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();
        __Pausable_init();
        baseToken = _baseToken;
        stablecoinUSDAddr = _USDTokenAddr;
    }

    event _Deposit(uint256 datetime, address contractaddress, uint256 rate, uint256 depositAmount, uint256 shares);
    event _Withdraw(uint256 datetime, address contractaddress, uint256 rate, uint256 avrCost, uint256 withdrawAmount, uint256 shares);


    function getVaultValues() external virtual view returns (uint256);
    function _getVaultValues() internal virtual view returns (uint256);
    function getUnitPrice()  external virtual view returns (uint256);
    function _getUnitPrice() internal virtual view returns (uint256);   
    function getVaultValuesInUSD() external virtual view returns (uint256);        
    function getUnitPriceInUSD()  external virtual view returns (uint256);
    function deposit(uint256 amount) external virtual returns (uint256);
    function withdraw(uint256 amount) external virtual returns (uint256);

    function setEmitEvent(address _addr) external onlyOwner {
        require(_addr != address(0), "_addr input is 0");
         emitEvent = IxWinEmitEvent(_addr);
    }

    function updateUSDAddr(address _newUSDAddr) external onlyOwner {
        require(_newUSDAddr != address(0), "_newUSDAddr input is 0");
        stablecoinUSDAddr = _newUSDAddr;
    }

    function setPause() external onlyOwner {
        _pause();
    }

    function setUnPause() external onlyOwner {
        _unpause();
    }


}