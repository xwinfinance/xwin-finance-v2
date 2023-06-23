// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
// import "../Interface/IxWinSwap.sol";
// import "../Interface/IxWinSingleAssetInterface.sol";
// import "../xWinStrategyWithFee.sol";



// contract xWinStablecoinAlpha is xWinStrategyWithFee {
//     using SafeERC20Upgradeable for IERC20Upgradeable;

//     address public targetToken; // Cake token
    
//     IxWinSingleAssetInterface public _stableCoinStaking;
//     IxWinSingleAssetInterface public _targetTokenStaking;
//     IxWinSwap public swapEngine;
//     mapping(address => bool) public executors;
    
//     uint256 public lastInvestedBlock;
//     uint public reinvestDuration;
//     uint public totalDeposit;
    
//     event Pause();
//     event Unpause();

//     function initialize(
//         address _baseToken,
//         address _targetToken,
//         address _swapEngine,
//         address stableCoinStaking_,
//         address targetTokenStaking_,
//         address _USDTokenAddr,
//         uint256 _managerFee,
//         uint256 _performanceFee,
//         uint256 _collectionPeriod,
//         address _managerAddr
//     ) initializer external {
//         __xWinStrategyWithFee_init("xWIN Stable Alpha", "xSCA", _baseToken, _USDTokenAddr, _managerFee, _performanceFee, _collectionPeriod, _managerAddr);
//         targetToken = _targetToken;
//         swapEngine = IxWinSwap(_swapEngine);
//         _stableCoinStaking = IxWinSingleAssetInterface(stableCoinStaking_);
//         _targetTokenStaking = IxWinSingleAssetInterface(targetTokenStaking_);
//         lastInvestedBlock = block.number;
//         // Infinite approve
//         IERC20Upgradeable(baseToken).safeApprove(stableCoinStaking_, type(uint).max);
//         IERC20Upgradeable(targetToken).safeApprove(targetTokenStaking_, type(uint).max);
//         IERC20Upgradeable(baseToken).safeApprove(address(swapEngine), type(uint).max);
//         IERC20Upgradeable(targetToken).safeApprove(address(swapEngine), type(uint).max);

//         reinvestDuration = 28800;
//     }

    
//     modifier onlyExecutor {
//         require(
//             executors[msg.sender],
//             "executor: wut?"
//         );
//         _;
//     }

//     /**
//      * @notice Deposits funds into the Cake Vault
//      * @dev Only possible when contract not paused.
//      * @param _amount: number of tokens to deposit (in CAKE)
//      */
//     function deposit(uint256 _amount)
//         external
//         override
//         nonReentrant whenNotPaused returns (uint256) {
//         require(_amount > 0, "Nothing to deposit");
//         _calcFundFee();
//         IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
        
//         // record user balance in usdt
//         uint256 currentShares = _getMintQty(_amount);
//         _mint(msg.sender, currentShares);
        
//         totalDeposit = totalDeposit + _amount;

//         // remaining into baseToken
//         _stableCoinStaking.deposit(_amount);
        
//         if(!_isContract(msg.sender)){
//             emitEvent.FundEvent("deposit", address(this), msg.sender, getUnitPrice(), _amount, currentShares);
//         }
//         return currentShares;
//     }

//     function canSystemDeposit() external view returns (bool){
        
//         uint amtToSwap = getAmountToSwap(); 
//         return ((block.number - lastInvestedBlock) > reinvestDuration) && (amtToSwap > 0);
//     }

//     /**
//      * @notice Deposits funds into the Cake Vault
//      * @dev Only possible when contract not paused.
//      */
//     function systemDeposit()
//         external
//         onlyExecutor
//         nonReentrant 
//     {
//         require((block.number - lastInvestedBlock) > reinvestDuration, " wait till next reinvest cycle");
        
//         uint amtToSwap = getAmountToSwap(); 
//         if(amtToSwap > 0){
//             uint totalRefund = _stableCoinStaking.withdraw(amtToSwap);
//             uint btcOutput = swapEngine.swapTokenToToken(totalRefund, baseToken, address(targetToken));
//             _targetTokenStaking.deposit(btcOutput);
//             lastInvestedBlock = block.number;
//         }
//     }

//     function getAmountToSwap() public view returns (uint){
        
//         // total stable coin staked in the single asset
//         uint unitOwn = _stableCoinStaking.getUserBalance(address(this));
//         uint uprice = _stableCoinStaking.getUnitPrice();
//         uint olaStableBal = uprice * unitOwn / 1e18; 
//         uint tobeinvestInAmount = olaStableBal > totalDeposit ? olaStableBal - totalDeposit : 0;
//         uint tobeinvestInUnit = tobeinvestInAmount * 1e18 / uprice;
//         return tobeinvestInUnit;
//     }

//     function getVaultValues() public override view returns (uint vaultValue){                
//         return getVaultValuesInUSD();
//     }

//     function _getVaultValues() internal override view returns (uint vaultValue){                
//         return getVaultValuesInUSD();
//     }

//     function getVaultValuesInUSD() public override view returns (uint vaultValue){        
        
//         uint usdtBal = _convertTo18(IERC20Upgradeable(baseToken).balanceOf(address(this)), baseToken);
//         uint olaStableBal = getStableValues();
//         uint olaTargetBBal = getTargetValues();
//         return olaStableBal + olaTargetBBal + usdtBal;
//     }

//     function getStableValues() public view returns (uint vaultValue){        
//         return _stableCoinStaking.getUnitPriceInUSD() * _stableCoinStaking.getUserBalance(address(this)) / 1e18; 
//     }

//     function getTargetValues() public view returns (uint vaultValue){        
//         return _targetTokenStaking.getUnitPriceInUSD() * _targetTokenStaking.getUserBalance(address(this)) / 1e18; 
//     }
//     function getBaseValues() public view returns (uint vaultValue){        
//         return _convertTo18(IERC20Upgradeable(baseToken).balanceOf(address(this)), baseToken);
//     }

//     /**
//      * @notice Withdraws from funds from the Cake Vault
//      * @param _shares: Number of shares to withdraw
//      */
//     function withdraw(uint256 _shares)
//         external
//         override
//         nonReentrant whenNotPaused returns (uint)
//     {
        
//         require(_shares > 0, "Nothing to withdraw");
//         require(_shares <= IERC20Upgradeable(address(this)).balanceOf(msg.sender), "Withdraw exceeds balance");
//         _calcFundFee();
//         uint stableBalB4 = IERC20Upgradeable(baseToken).balanceOf(address(this)); 
//         uint redeemratio = _shares * 1e18 / getFundTotalSupply();
//         uint totalRefund = stableBalB4 * redeemratio / 1e18;
//         totalDeposit = totalDeposit - (totalDeposit * redeemratio / 1e18);
//         uint totalTargetTokenShares = _targetTokenStaking.getUserBalance(address(this)); 
//         uint totalStablecoinShares =  _stableCoinStaking.getUserBalance(address(this)); 

//         uint withdrawShares;
//         if(totalTargetTokenShares > 0){
//             withdrawShares = redeemratio * totalTargetTokenShares / 1e18;
//             withdrawShares = totalTargetTokenShares < withdrawShares ? totalTargetTokenShares: withdrawShares;
//             uint targetSwap = _targetTokenStaking.withdraw(withdrawShares);
//             // swap BTCB into USDT
//             if(targetSwap > 0) {
//                 uint swapOut = swapEngine.swapTokenToToken(targetSwap, address(targetToken), baseToken);
//                 totalRefund = totalRefund + swapOut; 
//             }
//         }
//         if(totalStablecoinShares > 0){
//             withdrawShares = redeemratio * totalStablecoinShares / 1e18;
//             withdrawShares = totalStablecoinShares < withdrawShares ? totalStablecoinShares: withdrawShares;
//             uint stableOut = _stableCoinStaking.withdraw(withdrawShares);
//             totalRefund = totalRefund + stableOut;
//         }
        
//         totalRefund = performanceWithdraw(_shares, totalRefund);
//         _burn(msg.sender, _shares);
        
//         if(totalRefund > 0) IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalRefund);
        
//         if(!_isContract(msg.sender)){
//             emitEvent.FundEvent("withdraw", address(this), msg.sender, getUnitPrice(), totalRefund, _shares);
//         }
//         return totalRefund;
//     }


//     function adminStakeStable() external onlyOwner {
//         _stableCoinStaking.deposit(IERC20Upgradeable(baseToken).balanceOf(address(this)));
//     }

//     function emergencyUnWindPosition() external whenPaused onlyOwner {
        
//         uint totalTargetTokenShares = _targetTokenStaking.getUserBalance(address(this)); 
//         uint totalStablecoinShares =  _stableCoinStaking.getUserBalance(address(this)); 
//         if(totalTargetTokenShares > 0){
//             _targetTokenStaking.withdraw(totalTargetTokenShares);
//         }
//         if(totalStablecoinShares > 0){  
//             _stableCoinStaking.withdraw(totalStablecoinShares);
//         }
//         // swap BTCB into USDT
//         uint targetSwap = IERC20Upgradeable(targetToken).balanceOf(address(this));
//         if(targetSwap > 0) swapEngine.swapTokenToToken(targetSwap, address(targetToken), baseToken);   
//     }

//     function setProperties(uint _reinvestDuration) external onlyOwner {
//         reinvestDuration = _reinvestDuration;
//     }

//     // Support multiple wallets or address as admin
//     function setExecutor(address _wallet, bool _allow) external onlyOwner {
//         executors[_wallet] = _allow;
//     }

//     function setSwapEngine(address _newSwapEngine) external onlyOwner  {        
//         swapEngine = IxWinSwap(_newSwapEngine);
//         if (IERC20Upgradeable(baseToken).allowance(address(this), address(swapEngine)) == 0) {
//             IERC20Upgradeable(baseToken).safeApprove(address(swapEngine), type(uint).max);
//         }
//         if (IERC20Upgradeable(targetToken).allowance(address(this), address(swapEngine)) == 0) {
//             IERC20Upgradeable(targetToken).safeApprove(address(swapEngine), type(uint).max);
//         }
//     }

//     /**
//      * @notice Withdraw unexpected tokens sent to the Cake Vault
//      */
//     function inCaseTokensGetStuck(address _token) external onlyOwner {
//         uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
//         IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
//     }

//     /**
//      * @notice Calculates the price per share
//      */
//     function getUnitPrice() public override view returns (uint256) {
//         return _getUnitPrice();
//     }

//     function _getUnitPrice() internal override view returns (uint256) {
//         uint vValue = getVaultValues();
//         return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : vValue * 1e18 / getFundTotalSupply();
//     }

//     function getUnitPriceInUSD() public override view returns (uint256) {
//         uint vValue = getVaultValuesInUSD();
//         return (getFundTotalSupply() == 0 || vValue == 0) ? 1e18 : vValue * 1e18 / getFundTotalSupply();
//     }

//     function getNextInvestBlock() external view returns (uint256) {
//         return lastInvestedBlock + reinvestDuration;
//     }

//     function getDecimals(address _token) private view returns (uint) {
//         return (10 ** ERC20Upgradeable(_token).decimals());
//     }
// }