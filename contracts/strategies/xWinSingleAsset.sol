pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IOlaFinance.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinSingleAsset is xWinStrategyWithFee {
    
    using SafeERC20Upgradeable for IERC20Upgradeable;

    
    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster; 
    OlaFinance public _OlaFinance; 
    RainMakerForOlaLens public _rainMaker;
    IERC20Upgradeable public lendingRewardToken;
    uint256 public smallRatio;
    mapping(address => bool) public executors;
    
    modifier onlyExecutor {
        require(
            executors[msg.sender],
            "executor: wut?"
        );
        _;
    }

    function initialize(
        string calldata name,
        string calldata symbol,
        address _baseToken,
        address _USDTokenAddr,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) initializer external {
        __xWinStrategyWithFee_init(name, symbol, _baseToken, _USDTokenAddr, _managerFee, _performanceFee, _collectionPeriod, _managerAddr);

        smallRatio = 100;
    }

    function init(
        address _swapEngine,
        address _lendingRewardToken,
        address _xWinPriceMaster
    ) external onlyOwner {
        require(address(lendingRewardToken) == address(0), "already called init");
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
        lendingRewardToken = IERC20Upgradeable(_lendingRewardToken);
    }
 
    function updateProperties(
        address olaFinance_,
        address rainMaker_
    ) external onlyOwner {
        require(olaFinance_ != address(0), "olaFinance is 0");
        require(rainMaker_ != address(0), "rainMaker is 0");
        require(address(_OlaFinance) == address(0), "Already initialized properties");
        _OlaFinance = OlaFinance(olaFinance_);
        _rainMaker = RainMakerForOlaLens(rainMaker_);
    }

    function getUserBalance(address _user)  public view returns (uint256) {        
        return IERC20Upgradeable(address(this)).balanceOf(_user);
    }

    function getSupplyRatePerBlock()  public view returns (uint256) {
        return _OlaFinance.supplyRatePerBlock();
    }

    function getBorrowRatePerBlock()  public view returns (uint256) {
        return _OlaFinance.borrowRatePerBlock();
    }

    function getUnitPrice()  public view override returns (uint256) {
        return _convertTo18(_getUnitPrice(), baseToken);
    }

    function _getUnitPrice() internal override view returns(uint256){
        uint vValue = _getVaultValues();
        return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : vValue * 1e18 / getFundTotalSupply();
    }

    function _getUnitPrice(uint256 fundvalue) internal view returns(uint256){
        return (getFundTotalSupply() == 0 || fundvalue == 0) ? 1e18 : _convertTo18(fundvalue * 1e18 / getFundTotalSupply(), baseToken);
    }


    function getUnitPriceInUSD()  public view override returns (uint256) {
        uint vValue = _getVaultValuesInUSD();
        return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : _convertTo18(vValue * 1e18 / getFundTotalSupply(), stablecoinUSDAddr);
    }

    function deposit(uint256 _amount) external override nonReentrant whenNotPaused returns (uint256) {
        return _deposit(_amount, 0);
    }

    function deposit(uint256 _amount, uint32 _slippage)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return _deposit(_amount, _slippage);
    }

    function _deposit(uint256 _amount, uint32 _slippage) internal returns (uint256) {

        require(_amount > 0, "Nothing to deposit");
        _calcFundFee();
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint currentShares = _getMintQty(_amount);        
        
        _mint(msg.sender, currentShares);
        
        if(!_isContract(msg.sender)){
            emitEvent.FundEvent("deposit", address(this), msg.sender, getUnitPrice(), _amount, currentShares);
        }
        return currentShares;
    }

    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused returns (uint256){
        return _withdraw(_amount, 0);
    }

    function withdraw(uint256 _amount, uint32 _slippage)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint)
    {
        return _withdraw(_amount, _slippage);
    }

    function _withdraw(uint256 _amount, uint32 _slippage) internal returns (uint256){
    
        require(_amount > 0, "Nothing to withdraw");
        require(_amount <= IERC20Upgradeable(address(this)).balanceOf(msg.sender), "Withdraw amount exceeds balance");
        _calcFundFee();
        // swap any comp available into target token so that it is included into fund total values
        uint256 redeemratio = _amount * 1e18 / getFundTotalSupply();
        
        uint targetBalB4 = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint totalRefund = redeemratio * targetBalB4 / 1e18;
        
        uint totalOlaAmount = IERC20Upgradeable(address(_OlaFinance)).balanceOf(address(this));
        uint withdrawOlaAmt = redeemratio * totalOlaAmount / 1e18;
        withdrawOlaAmt = totalOlaAmount < withdrawOlaAmt ? totalOlaAmount: withdrawOlaAmt;
        if(withdrawOlaAmt > 0) _removeOla(withdrawOlaAmt);
        uint targetBalAfter = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetDiff = targetBalAfter - targetBalB4;
        totalRefund = totalRefund + targetDiff;
        
        _burn(msg.sender, _amount);
        IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalRefund);
        if(!_isContract(msg.sender)){
            emitEvent.FundEvent("withdraw", address(this), msg.sender, getUnitPrice(), totalRefund, _amount);
        }
        return totalRefund;
    }

    // Get total vault value in target token i.e. BTCB
    function getVaultValues() external override view returns (uint vaultValue){                
        return _convertTo18(_getVaultValues(), baseToken);
    }

    // Get total vault value in base ccy i.e. USDT
    function getVaultValuesInUSD() external override view returns (uint vaultValue){        
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr); 
    }

    function _getVaultValues() internal override view returns (uint256){
        uint valueInUSD = _getVaultValuesInUSD();
        uint rate = xWinPriceMaster.getPrice(stablecoinUSDAddr, baseToken); 
        return (rate * valueInUSD / getDecimals(address(stablecoinUSDAddr)));
    }
    
    function _getVaultValuesInUSD() internal view returns (uint256){
        uint exRateTargetBase = xWinPriceMaster.getPrice(baseToken, stablecoinUSDAddr); 
        uint exRateLendingBase = xWinPriceMaster.getPrice(address(lendingRewardToken), stablecoinUSDAddr); 
        
        // staking target token balance
        uint exchangeRateStaking = _OlaFinance.exchangeRateStored();
        uint balanceStakingToken = _OlaFinance.balanceOf(address(this));
        uint balanceStakingTokenInUSD = balanceStakingToken == 0 ? 0 : balanceStakingToken * exchangeRateStaking * exRateTargetBase / getDecimals(baseToken)  / 1e18;
        
        // target token balance in the contract
        uint baseTokenBal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        baseTokenBal = exRateTargetBase * baseTokenBal / getDecimals(baseToken); 
        
        // accrueComp accumulated during staking
        uint accruedComp = getAccruedComp(); 
        uint accruedCompInUSD = exRateLendingBase *  accruedComp / getDecimals(address(lendingRewardToken));
        
        return balanceStakingTokenInUSD + baseTokenBal + accruedCompInUSD;
    }
    

    function canReclaimRainMaker() public view returns (bool) {

        uint fundValueInUSD = _getVaultValuesInUSD();
        uint accruedComp = getAccruedComp(); 
        uint exRateLendingBase = xWinPriceMaster.getPrice(address(lendingRewardToken), stablecoinUSDAddr); 
        uint accruedCompInUSD = exRateLendingBase *  accruedComp;
        uint percentage = accruedCompInUSD * 10000 / fundValueInUSD / getDecimals(address(lendingRewardToken));
        return percentage > smallRatio;        
    }

    function canSystemDeposit() public view returns (bool){
        
        uint fundValue = _getVaultValues();
        if(fundValue == 0) return false;
        uint targetbal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint percentage = targetbal * 10000 / fundValue;
        return percentage > smallRatio;
    }

    function systemDeposit()
        external 
        onlyExecutor
        nonReentrant 
    {
        _depositOla();
    }

    function emergencyUnWindPosition() external whenPaused nonReentrant onlyOwner {
        uint balanceToken = _OlaFinance.balanceOf(address(this));
        _removeOla(balanceToken);
        if (address(_rainMaker) != address(0)){
            if(_rainMaker.venusAccrued(address(this)) > 0){
                _rainMaker.claimVenus(address(this));
            }
        }
    }

    function reinvestClaimComp() public nonReentrant {
        if (address(_rainMaker) == address(0)) return;
        if(_rainMaker.venusAccrued(address(this)) > 0){
            _rainMaker.claimVenus(address(this));
        }
        uint bal = lendingRewardToken.balanceOf(address(this));
        if(bal > 0){
            lendingRewardToken.safeIncreaseAllowance(address(swapEngine), bal);
            swapEngine.swapTokenToToken(bal, address(lendingRewardToken), baseToken); 
            _depositOla();
        }
    }

    function getAccruedComp() public view returns (uint) {
        if (address(_rainMaker) == address(0)) return 0;
        return _rainMaker.venusAccrued(address(this));
    }

    function getStrategyInfo() external view returns (
        address targetaddress, 
        address rewardaddress
        ) {
        return (baseToken, address(lendingRewardToken));
    }

    function _depositOla() internal {   

        uint bal = IERC20Upgradeable(baseToken).balanceOf(address(this));  
        if(bal > 0){
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(_OlaFinance), bal);
            _OlaFinance.mint(bal);
        }  
    }
    
    function _removeOla(uint _amount) internal {        
        _OlaFinance.redeem(_amount);
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    /// @dev update small ratio
    function updateSmallRatio(uint _ratio) external onlyOwner  {        
        smallRatio = _ratio;
    }

    function setSwapEngine(address _newSwapEngine) external onlyOwner  {        
        swapEngine = IxWinSwap(_newSwapEngine);
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner  {        
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

    function setLendingRewardToken(address _newRewardToken) public onlyOwner {
        lendingRewardToken = IERC20Upgradeable(_newRewardToken);
    }

    function setRainMaker(address rainMaker_) public onlyOwner {
        _rainMaker = RainMakerForOlaLens(rainMaker_);
    }

}