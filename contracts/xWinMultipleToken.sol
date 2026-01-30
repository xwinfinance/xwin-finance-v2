// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./Interface/IxWinSwap.sol";
import "./Interface/IxWinStrategy.sol";
import "hardhat/console.sol";

contract xWinMultipleToken is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IxWinSwap public xWinSwap; // contract address for swapping tokens

    mapping(address => bool) public isSupportedToken;
    mapping(address => bool) public isSupportedFund;
    address public baseToken;

    function initialize(address _xWinSwap, address _baseToken) public initializer{
        __Ownable_init();
        xWinSwap = IxWinSwap(_xWinSwap);
        baseToken = _baseToken;
        isSupportedToken[_baseToken] = true;
    }

    modifier onlySupported(address token) {
        require(isSupportedToken[token], "TOKEN_NOT_SUPPORTED");
        _;
    }

    modifier onlySupportedFunds(address fund) {
        require(isSupportedFund[fund], "FUND_NOT_SUPPORTED");
        _;
    }

    function setSupportedToken(address token, bool supported) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        isSupportedToken[token] = supported;
    }

    function setSupportedFund(address fund, bool supported) external onlyOwner {
        require(fund != address(0), "ZERO_FUND");
        isSupportedFund[fund] = supported;
    }

    function deposit(uint256 _amount, uint32 _slippage, address token, address fund) public nonReentrant onlySupported(token) onlySupportedFunds(fund) returns (uint256) {
        return _deposit(_amount, _slippage, token, fund);
    }

    function deposit(uint256 _amount, address token, address fund) external nonReentrant onlySupported(token) onlySupportedFunds(fund) returns (uint256) {
        return _deposit(_amount, 0, token, fund);
    }

    function _deposit(uint256 _amount, uint32 _slippage, address token, address fund) internal returns (uint256)  {
        require(_amount > 0, "Amount must be greater than zero");
        uint amtOut;
        if(token != baseToken){
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20Upgradeable(token).safeIncreaseAllowance(address(xWinSwap), _amount);
            amtOut = xWinSwap.swapTokenToToken(_amount, token, baseToken);
        } else{
            IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
            amtOut = _amount;
        }
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(fund), amtOut);
        uint amtDeposit =  IxWinStrategy(fund).deposit(amtOut, _slippage);
        IERC20Upgradeable(fund).safeTransfer(msg.sender, amtDeposit);
        return amtDeposit;
    }

    function withdraw(uint256 _amount, uint32 _slippage, address token, address fund) public nonReentrant onlySupported(token) onlySupportedFunds(fund) {
        return _withdraw(_amount, _slippage, token, fund);
    }

    function withdraw(uint256 _amount, address token, address fund) external nonReentrant onlySupported(token) onlySupportedFunds(fund) {
        return _withdraw(_amount, 0, token, fund);
    }

    function _withdraw(uint256 _amount, uint32 _slippage, address token, address fund) internal {
        require(_amount > 0, "No balance to withdraw");
        require(
            _amount <= IERC20Upgradeable(fund).balanceOf(msg.sender),
            "Withdraw amount exceeds balance"
        );

        IERC20Upgradeable(fund).safeTransferFrom(msg.sender, address(this), _amount);
        uint amtWithdrawn = IxWinStrategy(fund).withdraw(_amount, _slippage);
        if(token != baseToken){
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(xWinSwap), amtWithdrawn);
            uint amtOut = xWinSwap.swapTokenToToken(amtWithdrawn, baseToken, token);
            IERC20Upgradeable(token).safeIncreaseAllowance(msg.sender, amtOut);
            IERC20Upgradeable(token).safeTransfer(msg.sender, amtOut);
        } else {
            IERC20Upgradeable(token).safeIncreaseAllowance(msg.sender, amtWithdrawn);
            IERC20Upgradeable(token).safeTransfer(msg.sender, amtWithdrawn);
        }
    }

    function isTokenSupported(address token) external view returns (bool) {
        return isSupportedToken[token];
    }

    function isFundSupported(address fund) external view returns (bool) {
        return isSupportedFund[fund];
    }
}