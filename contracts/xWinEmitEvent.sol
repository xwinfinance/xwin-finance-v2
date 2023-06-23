// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract xWinEmitEvent is OwnableUpgradeable {

    modifier onlyExecutor {
        require(
            executors[msg.sender],
            "executor: wut?"
        );
        _;
    }

    modifier onlyAdmin {
        require(
            admins[msg.sender],
            "admin: wut?"
        );
        _;
    }

    mapping(address => bool) public executors;
    mapping(address => bool) public admins;

    event FundActivity(string eventtype, address contractaddress, address useraddress, uint rate, uint outAmount, uint shares);
    event FeeCollected(string eventtype, address contractaddress, uint256 fee);
    event FeeTransfered(address token,uint amount , address _managerWallet);

    function initialize() initializer external {
        __Ownable_init();
        executors[msg.sender] = true;
        admins[msg.sender] = true;
    }

    function FeeEvent(string calldata _eventtype, address _contractaddress, uint256 _fee) external onlyExecutor {
        emit FeeCollected(_eventtype, _contractaddress, _fee);
    }

    function FundEvent(
        string calldata _type,
        address _contractaddress, 
        address _useraddress, 
        uint _rate, 
        uint _amount, 
        uint _shares
    ) external onlyExecutor {
        emit FundActivity(_type, _contractaddress, _useraddress, _rate, _amount, _shares);
    }

    function feeTransfered(
        address _token,
        uint _amount,
        address _managerWallet
    ) public onlyExecutor {
        emit FeeTransfered(_token, _amount, _managerWallet);
    }

    
    // Support multiple wallets or address as admin
    function setExecutor(address _address, bool _allow) external onlyAdmin {
        executors[_address] = _allow;
    }

    // Support multiple wallets or address as admin
    function setAdmin(address _address, bool _allow) external onlyOwner {
        admins[_address] = _allow;
    }

}