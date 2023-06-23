// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IxWinEmitEvent {

    function feeTransfered(
        address _token,
        uint _amount,
        address _contractAddress

    ) external;


    function FeeEvent(string memory _eventtype, address _contractaddress, uint256 _fee) external;
    function FundEvent(
        string memory _type,
        address _contractaddress, 
        address _useraddress, 
        uint _rate, 
        uint _amount, 
        uint _shares
    ) external;

    function setExecutor(address _address, bool _allow) external;
}
