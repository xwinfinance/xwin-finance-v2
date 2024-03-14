pragma solidity ^0.8.0;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../xWinStrategyWithFee.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";
import "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinSingleAssetAave is xWinStrategyWithFee {
    
    using SafeERC20Upgradeable for IERC20Upgradeable;

    
    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster; 
    IPool public aavePool;
    IPoolDataProvider public aavePoolDataProvider;
    IERC20Upgradeable public targetToken; // aToken e.g. aWETH, aUSDC
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
        address _swapEngine,
        address _xWinPriceMaster,
        address _USDTokenAddr,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) initializer external {
        __xWinStrategyWithFee_init(name, symbol, _baseToken, _USDTokenAddr, _managerFee, _performanceFee, _collectionPeriod, _managerAddr);
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
        smallRatio = 100;
    }

    function updateProperties(
        address _targetToken,
        address _pool,
        address _aavePoolDataProvider
    ) external onlyOwner {
        require(_targetToken != address(0), "targetToken is 0");
        require(_pool != address(0), "pool is 0");
        require(_aavePoolDataProvider != address(0), "poolDataProvider is 0");
        require(address(targetToken) == address(0), "already initialized properties");
        targetToken = IERC20Upgradeable(_targetToken);
        aavePool = IPool(_pool);
        aavePoolDataProvider = IPoolDataProvider(_aavePoolDataProvider);
    }

    function getUserBalance(address _user)  public view returns (uint256) {        
        return IERC20Upgradeable(address(this)).balanceOf(_user);
    }

    // need to divide by 1e27 to get APR in %
    function getSupplyRate()  public view returns (uint256) {
        (
            ,
            ,
            ,
            ,
            ,
            uint256 liquidityRate,
            ,
            ,
            ,
            ,
            ,
        )= aavePoolDataProvider.getReserveData(baseToken);
        return liquidityRate;
    }

    function getUnitPrice()  public view override returns (uint256) {
        return _convertTo18(_getUnitPrice(), baseToken);
    }

    function _getUnitPrice() internal override view returns(uint256){
        uint vValue = _getVaultValues();
        return (getFundTotalSupply() == 0 || vValue == 0) ? 10**decimals() : vValue * 1e18 / getFundTotalSupply();
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
        uint256 up = _getUnitPrice();
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
        uint currentShares = _getMintQty(up);        
        
        _mint(msg.sender, currentShares);

        if(!_isContract(msg.sender)){
            emitEvent.FundEvent("deposit", address(this), msg.sender, getUnitPrice(), _amount, currentShares);
        }
        return currentShares;

    }

    function _getMintQty(uint256 _unitPrice) internal override view returns (uint256 mintQty)  {
        
        uint256 vaultValue = _getVaultValues();
        uint256 totalSupply = getFundTotalSupply();
        if(totalSupply == 0) return _convertTo18(vaultValue, baseToken); 
        uint256 newTotalSupply = vaultValue * 1e18 / _unitPrice;
        mintQty = newTotalSupply - totalSupply;
        return mintQty;
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

        // swap any comp available into target token so that it is included into fund total values
        uint256 redeemratio = _amount * 1e18 / getFundTotalSupply();
        
        uint baseBalB4 = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint totalRefund = redeemratio * baseBalB4 / 1e18;
        
        uint totalAaveAmount = IERC20Upgradeable(targetToken).balanceOf(address(this));
        uint withdrawAaveAmt = redeemratio * totalAaveAmount / 1e18;
        withdrawAaveAmt = totalAaveAmount < withdrawAaveAmt ? totalAaveAmount: withdrawAaveAmt;
        if(withdrawAaveAmt > 0) aavePool.withdraw(baseToken, withdrawAaveAmt, address(this));
        uint baseBalAfter = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetDiff = baseBalAfter - baseBalB4;
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
        // base token balance, target token balance
        // aToken is pegged 1:1 to underlying token
        // example: aWETH 1:1 WETH
        uint baseTokenBal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetTokenBal = targetToken.balanceOf(address(this));
        return (baseTokenBal + targetTokenBal);
    }
    
    function _getVaultValuesInUSD() internal view returns (uint256){

        uint baseTokenUSDPrice = xWinPriceMaster.getPrice(baseToken, stablecoinUSDAddr);
        return  _getVaultValues() * baseTokenUSDPrice / getDecimals(baseToken);
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
        _depositAave();
    }

    function emergencyUnWindPosition() external whenPaused nonReentrant onlyOwner {
        uint balanceToken = targetToken.balanceOf(address(this));
        _removeAave(balanceToken);
    }


    function _depositAave() internal {   

        uint bal = IERC20Upgradeable(baseToken).balanceOf(address(this));  
        if(bal > 0){
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(aavePool), bal);
            aavePool.supply(baseToken, bal, address(this), 0);
        }  
    }
    
    function _removeAave(uint _amount) internal {    
        aavePool.withdraw(baseToken, _amount, address(this));
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

}