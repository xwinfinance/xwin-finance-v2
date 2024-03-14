// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./Interface/IxWinSingleAssetInterface.sol";
import "./Interface/IxWinTradingInterface.sol";
import "./Interface/IxWinSwap.sol";

contract xWinSystemExecutor is OwnableUpgradeable {
    struct SwapInfo {
        address xWinSwapAddr;
        address router;
        address fromToken;
        address toToken;
        address[] path;
        uint256 slippage;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    mapping(address => bool) public executors;

    function initialize() public initializer {
        __Ownable_init();
        executors[msg.sender] = true;
    }

    function runSystemDeposit(
        address[] calldata _addresses
    ) external onlyExecutor {
        for (uint256 i = 0; i < _addresses.length; i++) {
            IxWinSingleAssetInterface _obj = IxWinSingleAssetInterface(
                _addresses[i]
            );
            if (_obj.canSystemDeposit()) {
                _obj.systemDeposit();
            }
        }
    }

    function runSystemReinvestReclaim(
        address[] calldata _addresses
    ) external onlyExecutor {
        for (uint256 i = 0; i < _addresses.length; i++) {
            IxWinSingleAssetInterface _obj = IxWinSingleAssetInterface(
                _addresses[i]
            );
            if (_obj.canReclaimRainMaker()) {
                _obj.reinvestClaimComp();
            }
        }
    }

    function runSystemReTrade(
        address[] calldata _addresses
    ) external onlyExecutor {
        for (uint256 i = 0; i < _addresses.length; i++) {
            IxWinTradingInterface _obj = IxWinTradingInterface(_addresses[i]);
            if (_obj.isReTrade()) {
                _obj.systemReTrade();
            }
        }
    }

    function runSystemAddTokenPath(
        SwapInfo[] calldata swapInfos
    ) external onlyExecutor {
        for (uint256 i = 0; i < swapInfos.length; i++) {
            IxWinSwap _obj = IxWinSwap(swapInfos[i].xWinSwapAddr);
            _obj.addTokenPath(
                swapInfos[i].router,
                swapInfos[i].fromToken,
                swapInfos[i].toToken,
                swapInfos[i].path,
                swapInfos[i].slippage
            );
        }
    }

    function setExecutor(address _address, bool _allow) external onlyOwner {
        executors[_address] = _allow;
    }
}
