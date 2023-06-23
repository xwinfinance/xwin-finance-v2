// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Interface/IxWinEmitEvent.sol";

contract xWinSplitFeeWallet is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct Manager {
        address managerAddress;
        uint[] ratio;
    }

    Manager[] public managers;
    address[] public tokens;
    IxWinEmitEvent public emitEvent;
    uint public startBlock;
    uint public period;

    function initialize(
        address _emitEvent,
        Manager[] calldata _managers
    ) external initializer {
        __Ownable_init();
        startBlock = block.number;
        period = 10512000;
        emitEvent = IxWinEmitEvent(_emitEvent);

        uint ratioLength = _managers[0].ratio.length;
        for (uint i = 0; i < _managers.length; i++) {
            require(
                _managers[i].ratio.length == ratioLength,
                "manager ratio array length mismatch"
            );
        }

        for (uint j = 0; j < _managers[0].ratio.length; j++) {
            uint sum;
            for (uint i = 0; i < _managers.length; i++) {
                sum = sum + _managers[i].ratio[j];
            }
            require(sum == 10000, "Ratios must be equal to 100%");
        }
        for (uint i = 0; i < _managers.length; i++) {
            managers.push(_managers[i]);
        }
    }

    function restateManagers(Manager[] memory _managers) external onlyOwner {
        delete managers;

        uint ratioLength = _managers[0].ratio.length;
        for (uint i = 0; i < _managers.length; i++) {
            require(
                _managers[i].ratio.length == ratioLength,
                "manager ratio array length mismatch"
            );
        }

        for (uint j = 0; j < _managers[0].ratio.length; j++) {
            uint sum;
            for (uint i = 0; i < _managers.length; i++) {
                sum = sum + _managers[i].ratio[j];
            }
            require(sum == 10000, "Ratios must be equal to 100%");
        }
        for (uint i = 0; i < _managers.length; i++) {
            managers.push(_managers[i]);
        }
    }

    function distributeFees() external returns (bool) {
        uint periodToUse = (block.number - startBlock) / period;
        if (periodToUse > managers[0].ratio.length - 1) {
            periodToUse = managers[0].ratio.length - 1;
        }

        for (uint i = 0; i < tokens.length; i++) {
            uint tokenBalance = IERC20Upgradeable(tokens[i]).balanceOf(
                address(this)
            );
            for (uint j = 0; j < managers.length; j++) {
                IERC20Upgradeable(tokens[i]).safeTransfer(
                    managers[j].managerAddress,
                    (tokenBalance * managers[j].ratio[periodToUse]) / 10000
                );
            }
            emitEvent.feeTransfered(tokens[i], tokenBalance, address(this));
        }

        return true;
    }

    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "empty input");
        tokens.push(_token);
    }

    // remove from array, shortening it
    function removeToken(uint index) external onlyOwner {
        require(index < tokens.length);
        tokens[index] = tokens[tokens.length - 1];
        tokens.pop();
    }

    function updateEventEmitter(address _newEmitEvent) external onlyOwner {
        emitEvent = IxWinEmitEvent(_newEmitEvent);
    }

    function updateStartBlock(uint _newStartBlock) external onlyOwner {
        startBlock = _newStartBlock;
    }

    function setPeriod(uint _newPeriod) external onlyOwner {
        period = _newPeriod;
    }
}
