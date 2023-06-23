// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IFundV2 {
    function collectPlatformFee() external;
    function setPause() external;
    function setUnPause() external;
    function MoveNonIndexNameToBase(address _tokenaddress) external returns (uint256 balanceToken, uint256 swapOutput);
    function emergencyRedeem(uint256 redeemUnit, address _investorAddress) external;
    function updateOtherProperties(uint256 newCycle, uint256 _ratio, uint256 _unitpriceMultiplier) external;
    function updatePlatformProperty(address newPlatformWallet, uint256 newPlatformFee) external;
    function updateManagerProperty(address newRebManager, address newManager, uint256 newFeebps) external;
    function setPerformanceFee(uint256 _performFee) external;
    function updatexWinEngines(address _xwinPricesMaster, address _xwinSwap) external;
    function updateUSDAddr(address _newUSDAddr) external;
    function updateLockedStakingAddress(address _lockedStaking) external;
    function addContractWaiveFee(address _contract) external;
    function removeContractWaiveFee(address _contract) external;
    function init(
        uint256 _managerFee, 
        uint256 _performFee,
        uint256 _platformFee,
        bool _openForPublic,
        uint256 _UPMultiplier,
        uint256 _rebalancePeriod,
        uint256 _blocksPerDay,
        uint256 _smallRatio
    ) external;
    function createTargetNames(address[] calldata _toAddresses,  uint256[] calldata _targetWeight) external;
    function updateSmallRatio(uint256 _ratio) external;
    function updateBlockPerday(uint256 _blocksPerDay) external;  
    function collectFundFee() external; 
    function getManagerAddr() external view returns (address manager, address rebManager);
    function setValidInvestor(address _wallet, bool _allow) external;
    function getPlatformDetails() external view returns (uint256 platformFee, address platformWallet);
    function withdraw(uint256 amount) external returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function setEmitEvent(address _addr) external;
    function setOpenForPublic(bool _allow) external;
    // function setUnitPriceMultiplier(uint256 _unitpriceMultiplier) external;
    function getUnitPrice() external view returns (uint256);
    function getUnitPriceInUSD() external view returns (uint256);
    function getUserAveragePrice(address _user) external view returns (uint256 shares, uint256 avgPrice);
    function decimals() external view returns (uint8);
}