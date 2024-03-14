pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./xWinStrategy.sol";
import "./Interface/ILockedStake.sol";
// import "hardhat/console.sol";

abstract contract xWinStrategyWithFee is xWinStrategy {
     
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => bool) public waivedPerformanceFees;
    uint256 public performanceFee; // 10%
    uint256 public managerFee;
    uint256 public pendingMFee;
    uint256 public collectionPeriod; // Tomorrow 12PM
    uint256 public collectionBlock;
    uint256 public prevCollectionBlock;
    uint256 public watermarkUnitprice;
    address public strategyManager;
    uint256 public lastManagerFeeCollection;
    uint256 public blocksPerDay;
    uint256 public pendingNewPerformanceFee;
    address public lockingAddress;
    uint256[10] private __gap;
    
    function __xWinStrategyWithFee_init(
        string memory _name,
        string memory _symbol,
        address _baseToken,
        address _USDTokenAddr,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) onlyInitializing internal {
        require(_managerFee <= 300, "Strategy Fee capped at 3%");
        require(_performanceFee <= 2000, "Performance Fee capped at 20%");
        require(_managerAddr != address(0), "_managerAddr input 0");
        __xWinStrategy_init(_name, _symbol, _baseToken, _USDTokenAddr);
        performanceFee = _performanceFee;
        managerFee = _managerFee;
        collectionPeriod = _collectionPeriod;
        strategyManager = _managerAddr;
        lastManagerFeeCollection = block.number;
        collectionBlock = block.number + collectionPeriod;
        prevCollectionBlock = block.number;
        watermarkUnitprice = (10 ** ERC20Upgradeable(_baseToken).decimals());
        blocksPerDay = 28800;
    }

    function updateLockedStakingAddress(address _lockedStaking) external onlyOwner {
        lockingAddress = _lockedStaking;
    }

    function canCollectPerformanceFee() public virtual view returns (bool) {
        return block.number > collectionBlock;
    }

    function _calcFundFee() internal virtual {
        uint256 totalblock = block.number - lastManagerFeeCollection;
        lastManagerFeeCollection = block.number;
        uint256 supply = getFundTotalSupply();

        if(supply == 0) return;

        // calculate number of shares to create per block
        uint256 uPerBlock = supply * 10000 / (10000 - managerFee);
        uPerBlock = uPerBlock - supply; // total new blocks generated in a year
        uPerBlock = uPerBlock / (blocksPerDay * 365);

        // award the shares
        pendingMFee = pendingMFee + (totalblock * uPerBlock);
    }

    function collectFundFee() external virtual {
        _calcFundFee();
        uint256 toAward = pendingMFee;
        pendingMFee = 0;
        _mint(strategyManager, toAward);
    }

    function collectPerformanceFee() external virtual {
        require(canCollectPerformanceFee(), "block number has not passed collection block");
        uint unitPrice = _getUnitPrice();
        if (watermarkUnitprice < unitPrice) {
            uint totalUnits = getFundTotalSupply();
            uint totalProfit = (unitPrice - watermarkUnitprice) * totalUnits / 1e18;
            // collect performance fee
            uint feeAmt = totalProfit * performanceFee / 10000;
            uint newShares = _getMintQty(feeAmt); 
            _mint(strategyManager, newShares);
            watermarkUnitprice = unitPrice;
        }
        collectionBlock = block.number + collectionPeriod;
        prevCollectionBlock = block.number;

        // check if there is a pending update to performfee
        if (pendingNewPerformanceFee > 0) {
            performanceFee = pendingNewPerformanceFee;
            pendingNewPerformanceFee = 0;
        }
        // emit event
    }

    function performanceWithdraw(uint256 _withdrawUnits, uint256 _amtOut) internal returns (uint256) {
        if(performanceFee == 0) return _amtOut;
        uint256 unitPrice = _getUnitPrice();
        if (unitPrice <= watermarkUnitprice || waivedPerformanceFees[msg.sender]) {
            return _amtOut; // no profit => no performance fee, manager => no performance fee
        }
        
        uint blockDiff = block.number - prevCollectionBlock;
        if (blockDiff > collectionPeriod) {
            blockDiff = collectionPeriod;
        }
        uint256 profit = (unitPrice - watermarkUnitprice) * _withdrawUnits * blockDiff / collectionPeriod / 1e18;
        uint256 fee = profit * performanceFee / 10000;
        
        if (lockingAddress != address(0)) {
            uint256 discount = ILockedStake(lockingAddress).getFavor(msg.sender);
            fee = fee - ((fee * discount) / 10000);
        }
        IERC20Upgradeable(baseToken).safeTransfer(strategyManager, fee);
        return  _amtOut - fee;
    }

    /// @dev Calc qty to issue during subscription 
    function _getMintQty(uint256 _depositAmt) internal virtual view returns (uint256 mintQty)  {
        
        _depositAmt = _convertTo18(_depositAmt, address(baseToken));
        uint256 totalFundAfter = this.getVaultValues();
        uint256 totalFundB4 = totalFundAfter > _depositAmt ?  totalFundAfter - _depositAmt : 0;
        mintQty = _getNewFundUnits(totalFundB4, totalFundAfter);
        return (mintQty);
    }

    /// @dev Mint unit back to investor
    function _getNewFundUnits(uint256 totalFundB4, uint256 totalValueAfter) 
        internal virtual view returns (uint256){
          
        if(totalValueAfter == 0) return 0;
        if(totalFundB4 == 0) return totalValueAfter; 

        uint256 totalUnitAfter = totalValueAfter * getFundTotalSupply() / totalFundB4;
        uint256 mintUnit = totalUnitAfter - getFundTotalSupply();
        
        return mintUnit;
    }

    function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner {
        require(_newPerformanceFee <= 2000, "Performance Fee capped at 20%");
        pendingNewPerformanceFee = _newPerformanceFee;
    }

    function setManagerFee(uint256 _newManagerFee) external onlyOwner {
        require(_newManagerFee <= 300, "Strategy Fee capped at 3%");
        managerFee = _newManagerFee;
    }

    function setPerformanceCollectionPeriod(uint256 _newPeriod) external onlyOwner {
        collectionPeriod = _newPeriod;
    }

    function setBlockPerDay(uint256 _newBlocksPerDay) external onlyOwner {
        blocksPerDay = _newBlocksPerDay;
    }

    function getFundTotalSupply() public virtual view returns(uint256) {
        return totalSupply() + pendingMFee;
    }

    /// Get All the fund data needed for client
    function GetStrategyData() external view returns (
          address baseCcy,
          uint256 totalUnitB4,
          uint256 unitprice,
          uint256 fundvalue,
          uint256 unitpriceUSD,
          uint256 fundvalueUSD,
          string memory name,
          string memory symbol,
          uint256 managementFee,
          uint256 performFee,
          address mAddr,
          uint256 highWaterMarkPrice
        ){
            return (
                baseToken, 
                getFundTotalSupply(), 
                this.getUnitPrice(), 
                this.getVaultValues(),
                this.getUnitPriceInUSD(), 
                this.getVaultValuesInUSD(),
                this.name(),
                this.symbol(),
                managerFee,
                performanceFee,
                strategyManager,
                watermarkUnitprice
            );
    }

    function setManagerWallet(address _newManagerWallet) external onlyOwner {
        require(_newManagerWallet != address(0), "_newManagerWallet input is 0");
        strategyManager = _newManagerWallet;
    }

    function _convertTo18(uint value, address token) internal view returns (uint){
        uint diffDecimal = 18 - ERC20Upgradeable(token).decimals();
        return diffDecimal > 0 ? (value * (10**diffDecimal)) : value; 
    } 

    function _convertFrom18(uint value, address token) internal view returns (uint){
        uint diffDecimal = 18 - ERC20Upgradeable(token).decimals();
        return diffDecimal > 0 ? (value / (10**diffDecimal)) : value; 
    } 

    function addWaiveFee(address _contract) external onlyOwner {
        waivedPerformanceFees[_contract] = true; 
    }

    function removeWaiveFee(address _contract) external onlyOwner {
        waivedPerformanceFees[_contract] = false;
    }

    function _isContract(address addr) internal view returns (bool) {
        
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}