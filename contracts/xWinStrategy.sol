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

abstract contract xWinStrategy is
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice stablecoinUSDAddr is used for view functions with the 'inUSD' suffix.
    address public stablecoinUSDAddr;
    /// @notice baseToken for the fund/strategy, token for deposit, and token recieved on withdraw 
    address public baseToken;
    IxWinEmitEvent public emitEvent;
    uint256[10] private __gap;

    function __xWinStrategy_init(
        string memory name,
        string memory symbol,
        address _baseToken,
        address _USDTokenAddr
    ) internal onlyInitializing {
        require(_baseToken != address(0), "_baseToken input 0");
        require(_USDTokenAddr != address(0), "_USDTokenAddr input 0");
        __Ownable_init();
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();
        __Pausable_init();
        baseToken = _baseToken;
        stablecoinUSDAddr = _USDTokenAddr;
    }

    event _Deposit(
        uint256 datetime,
        address contractaddress,
        uint256 rate,
        uint256 depositAmount,
        uint256 shares
    );
    event _Withdraw(
        uint256 datetime,
        address contractaddress,
        uint256 rate,
        uint256 avrCost,
        uint256 withdrawAmount,
        uint256 shares
    );

    /// @notice Gets the total value of the tokens within the fund, value shown in baseToken
    function getVaultValues() external view virtual returns (uint256);

    function _getVaultValues() internal view virtual returns (uint256);

    /// @notice The unitprice of a share of this fund in baseToken
    function getUnitPrice() external view virtual returns (uint256);

    function _getUnitPrice() internal view virtual returns (uint256);

    /// @notice Gets the total value of the tokens within the fund, value shown in stablecoinUSDAddr
    function getVaultValuesInUSD() external view virtual returns (uint256);

    /// @notice The unitprice of a share of this fund, in stablecoinUSDAddr
    function getUnitPriceInUSD() external view virtual returns (uint256);

    /// Deposits baseToken into the fund, and receives shares based on the fund's unitPrice
    /// @param amount Amount of baseToken to deposit
    /// @return shares Amount of shares minted to depositor
    function deposit(uint256 amount) external virtual returns (uint256);

    /// Withdraws from the fund by burning shares, liquidating assets into baseToken and transfering to user
    /// @param amount Amount of shares to withdraw
    /// @return amount Amount of baseTokens transferred to depositor
    function withdraw(uint256 amount) external virtual returns (uint256);

    /// Deposits baseToken into the fund, and receives shares based on the fund's unitPrice
    /// @param amount Amount of baseToken to deposit
    /// @param slippage Slippage to use for any swaps during the process
    /// @return shares Amount of shares minted to depositor
    function deposit(
        uint256 amount,
        uint32 slippage
    ) external virtual returns (uint256);

    /// Withdraws from the fund by burning shares, liquidating assets into baseToken and transfering to user
    /// @param amount Amount of shares to withdraw
    /// @param slippage Slippage to use for any swaps during the process
    /// @return amount Amount of baseTokens transferred to depositor
    function withdraw(
        uint256 amount,
        uint32 slippage
    ) external virtual returns (uint256);

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
