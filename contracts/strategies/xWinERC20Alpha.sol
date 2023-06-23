// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinSingleAssetInterface.sol";
import "../Interface/IxWinPriceMaster.sol";
import "../xWinStrategyWithFee.sol";


contract xWinERC20Alpha is xWinStrategyWithFee {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public targetToken; // Cake token
    IERC20Upgradeable public _baseTokenStaking;
    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster; 
    mapping(address => bool) public executors;
    
    uint256 public lastInvestedBlock;
    uint public reinvestDuration;
    uint public totalDeposit;
    
    event Pause();
    event Unpause();

    function initialize(
        address _baseToken,
        address _USDTokenAddr,
        string calldata _name,
        string calldata _symbol,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) initializer external {
        __xWinStrategyWithFee_init(_name, _symbol, _baseToken, _USDTokenAddr, _managerFee, _performanceFee, _collectionPeriod, _managerAddr);
        lastInvestedBlock = block.number;
        reinvestDuration = 28800;
    }

    function init(
        IERC20Upgradeable _targetToken,
        address _swapEngine,
        address baseTokenStaking_,
        address _xWinPriceMaster
    ) external onlyOwner {
        require(address(targetToken) == address(0), "already called init");
        targetToken = _targetToken;
        swapEngine = IxWinSwap(_swapEngine);
        _baseTokenStaking = IERC20Upgradeable(baseTokenStaking_);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    
    modifier onlyExecutor {
        require(
            executors[msg.sender],
            "executor: wut?"
        );
        _;
    }

    /**
     * @notice Deposits funds into the Cake Vault
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in CAKE)
     */
    function deposit(uint256 _amount)
        external
        override
        nonReentrant whenNotPaused returns (uint256) {
        require(_amount > 0, "Nothing to deposit");
        _calcFundFee();
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        // record user balance in usdt
        uint256 currentShares = _getMintQty(_amount);
        _mint(msg.sender, currentShares);
        
        totalDeposit = totalDeposit + _amount;

        // remaining into stablecoin
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(_baseTokenStaking), _amount);
        IxWinSingleAssetInterface(address(_baseTokenStaking)).deposit(_amount);
        
        if(!_isContract(msg.sender)){
            emitEvent.FundEvent("deposit", address(this), msg.sender, getUnitPrice(), _amount, currentShares);
        }
        return currentShares;
    }

    function canSystemDeposit() external view returns (bool){
        
        uint amtToSwap = getAmountToSwap(); 
        return ((block.number - lastInvestedBlock) > reinvestDuration) && (amtToSwap > 0);
    }

    /**
     * @notice Deposits funds into the Cake Vault
     * @dev Only possible when contract not paused.
     */
    function systemDeposit()
        external
        onlyExecutor
        nonReentrant 
    {
        require((block.number - lastInvestedBlock) > reinvestDuration, " wait till next reinvest cycle");
        
        uint amtToSwap = getAmountToSwap(); 
        if(amtToSwap > 0){
            uint earnedInterest = IxWinSingleAssetInterface(address(_baseTokenStaking)).withdraw(amtToSwap);
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(swapEngine), earnedInterest);
            swapEngine.swapTokenToToken(earnedInterest, baseToken, address(targetToken));
            lastInvestedBlock = block.number;
        }
    }

    function getAmountToSwap() public view returns (uint){
        
        // total stable coin staked in the single asset
        uint unitOwn = _baseTokenStaking.balanceOf(address(this));
        uint uprice = xWinPriceMaster.getPrice(address(_baseTokenStaking), baseToken);
        uint olaStableBal = uprice * unitOwn / 1e18; 
        uint tobeinvestInAmount = olaStableBal > totalDeposit ? olaStableBal - totalDeposit : 0;
        uint tobeinvestInUnit = tobeinvestInAmount * 1e18 / uprice;
        return tobeinvestInUnit;
    }

    function getVaultValues() public override view returns (uint vaultValue) {
        return _convertTo18( _getVaultValues(), baseToken);
    }

    function _getVaultValues() internal override view returns (uint vaultValue) {                
        uint valueInUSD = _getVaultValuesInUSD();
        uint rate = xWinPriceMaster.getPrice(stablecoinUSDAddr, baseToken); 
        return (rate * valueInUSD / getDecimals(address(stablecoinUSDAddr)));
    }

    function getVaultValuesInUSD() public override view returns (uint vaultValue){        
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }

    function _getVaultValuesInUSD() internal view returns (uint vaultValue){        
        
        uint exRateTargetBase = xWinPriceMaster.getPrice(baseToken, stablecoinUSDAddr); 
        uint baseBal = IERC20Upgradeable(baseToken).balanceOf(address(this)); //ada
        uint baseBalUSD = exRateTargetBase * baseBal / getDecimals(baseToken); //ada in usd

        uint baseStakingUSD = 0;
        if (baseToken != address(_baseTokenStaking)) {
            uint baseStakingBal = _baseTokenStaking.balanceOf(address(this));
            uint baseStakingUP = xWinPriceMaster.getPrice(address(_baseTokenStaking), stablecoinUSDAddr);
            baseStakingUSD = baseStakingBal * baseStakingUP / getDecimals(address(_baseTokenStaking));
        }

        uint targetStakingBal = targetToken.balanceOf(address(this));
        uint targetStakingUP = xWinPriceMaster.getPrice(address(targetToken), stablecoinUSDAddr);
        uint targetStakingUSD = targetStakingBal * targetStakingUP / getDecimals(address(targetToken));
        return baseBalUSD + baseStakingUSD + targetStakingUSD;
    }

    function getStableValues() external view returns (uint vaultValue){        
        return xWinPriceMaster.getPrice(address(_baseTokenStaking), stablecoinUSDAddr) * _baseTokenStaking.balanceOf(address(this)) / 1e18; 
    }

    function getTargetValues() external view returns (uint vaultValue){        
        return xWinPriceMaster.getPrice(address(targetToken), stablecoinUSDAddr) * targetToken.balanceOf(address(this)) / 1e18; 
    }

    function getBaseValues() external view returns (uint vaultValue){        
        return _convertTo18(IERC20Upgradeable(baseToken).balanceOf(address(this)), baseToken);
    }

    /**
     * @notice Withdraws from funds from the Cake Vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares)
        external
        override
        nonReentrant whenNotPaused returns (uint)
    {
        
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= IERC20Upgradeable(address(this)).balanceOf(msg.sender), "Withdraw exceeds balance");
        _calcFundFee();
        uint stableBalB4 = IERC20Upgradeable(baseToken).balanceOf(address(this)); 
        uint redeemratio = _shares * 1e18 / getFundTotalSupply();
        uint totalRefund = stableBalB4 * redeemratio / 1e18;
        totalDeposit = totalDeposit - (totalDeposit * redeemratio / 1e18);
        uint totalTargetTokenShares = targetToken.balanceOf(address(this)); 
        uint totalBaseShares =  _baseTokenStaking.balanceOf(address(this)); 

        uint withdrawShares;
        if(totalTargetTokenShares > 0){
            withdrawShares = redeemratio * totalTargetTokenShares / 1e18;
            withdrawShares = totalTargetTokenShares < withdrawShares ? totalTargetTokenShares: withdrawShares;
            targetToken.safeIncreaseAllowance(address(swapEngine), withdrawShares);
            uint targetOut = swapEngine.swapTokenToToken(withdrawShares, address(targetToken), baseToken);
            totalRefund += targetOut;
        }
        if(totalBaseShares > 0){
            withdrawShares = redeemratio * totalBaseShares / 1e18;
            withdrawShares = totalBaseShares < withdrawShares ? totalBaseShares: withdrawShares;
            uint stableOut = IxWinSingleAssetInterface(address(_baseTokenStaking)).withdraw(withdrawShares);
            totalRefund += stableOut;
        }
        
        totalRefund = performanceWithdraw(_shares, totalRefund);
        _burn(msg.sender, _shares);
        
        if(totalRefund > 0) IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalRefund);
        
        if(!_isContract(msg.sender)){
            emitEvent.FundEvent("withdraw", address(this), msg.sender, getUnitPrice(), totalRefund, _shares);
        }
        return totalRefund;
    }

    function adminStakeStable() external onlyOwner {
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(_baseTokenStaking), IERC20Upgradeable(baseToken).balanceOf(address(this)));
        IxWinSingleAssetInterface(address(_baseTokenStaking)).deposit(IERC20Upgradeable(baseToken).balanceOf(address(this)));
    }

    function emergencyUnWindPosition() external whenPaused onlyOwner {
        
        uint totalTargetTokenShares = targetToken.balanceOf(address(this)); 
        uint totalBaseShares =  _baseTokenStaking.balanceOf(address(this)); 
        if(totalTargetTokenShares > 0){
            targetToken.safeIncreaseAllowance(address(swapEngine), totalTargetTokenShares);
            swapEngine.swapTokenToToken(totalTargetTokenShares, address(targetToken), baseToken);
        }
        if(totalBaseShares > 0){  
            IxWinSingleAssetInterface(address(_baseTokenStaking)).withdraw(totalBaseShares);
        } 
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner  {        
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function setProperties(uint _reinvestDuration) external onlyOwner {
        reinvestDuration = _reinvestDuration;
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    function setSwapEngine(address _newSwapEngine) external onlyOwner  {        
        swapEngine = IxWinSwap(_newSwapEngine);
    }

    /**
     * @notice Calculates the price per share
     */
    function getUnitPrice() public override view returns (uint256) {
        return _getUnitPrice();
    }

    function _getUnitPrice() internal override view returns (uint256) {
        uint vValue = getVaultValues();
        return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : vValue * 1e18 / getFundTotalSupply();
    }

    function getUnitPriceInUSD() public override view returns (uint256) {
        uint vValue = getVaultValuesInUSD();
        return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : vValue * 1e18 / getFundTotalSupply();
    }

    function getNextInvestBlock() external view returns (uint256) {
        return lastInvestedBlock + reinvestDuration;
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

}