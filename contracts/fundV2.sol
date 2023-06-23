pragma solidity ^0.8.0;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Interface/ILockedStake.sol";
import "./Library/xWinLib.sol";
import "./Interface/IxWinPriceMaster.sol";
import "./Interface/IxWinSwap.sol";
import "./xWinStrategy.sol";
import "./Interface/IWETH.sol";

contract FundV2 is xWinStrategy {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct userAvgPrice {
        uint256 shares;
        uint256 avgPrice;
    }

    mapping(address => bool) public validInvestors; // stores authourised addresses that can use the private fund
    mapping(address => userAvgPrice) public performanceMap; // mapping to store performance fee
    mapping (address => bool) public waivedPerformanceFees; // stores authourised addresses with fee waived
    mapping(address => uint256) public TargetWeight; // stores the weight of the target asset
    address[] public targetAddr; // list of target assets
    IxWinPriceMaster public priceMaster; // contract address of price Oracle
    IxWinSwap public xWinSwap; // contract address for swapping tokens
    address public lockingAddress;
    address public managerAddr;
    address public managerRebAddr;
    address public platformWallet;

    uint256 public lastFeeCollection;
    uint256 public nextRebalance;
    uint256 public pendingMFee;
    uint256 public pendingPFee;
    uint256 private baseTokenAmt;
    uint256 public managerFee;
    uint256 public platformFee;
    uint256 public smallRatio;
    uint256 private rebalanceCycle;
    uint256 public performFee;
    uint256 private blocksPerDay;
    uint256 public UPMultiplier;    
    bool public openForPublic;

    
    event Received(address, uint256);
    event ManagerFeeUpdate(uint256 fromFee, uint256 toFee, uint256 txnTime);
    event ManagerOwnerUpdate(address fromAddress, address toAddress, uint256 txnTime);

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _baseToken,
        address _USDAddr,
        address _manageraddr,
        address _managerRebaddr,
        address _platformWallet,
        address _lockedStaking
    ) initializer external {
        require(_baseToken != address(0) , "_baseToken Input 0");
        require(_USDAddr != address(0), "_USDAddr Input 0");
        require(_manageraddr != address(0), "_manageraddr Input 0");
        require(_managerRebaddr != address(0), "_managerRebaddr Input 0");
        require(_platformWallet != address(0), "_platformWallet Input 0");
        require(_lockedStaking != address(0), "_lockedStaking Input 0");
        
        __xWinStrategy_init(_name, _symbol, _baseToken, _USDAddr);
        managerAddr = _manageraddr;
        managerRebAddr = _managerRebaddr;
        platformWallet = _platformWallet;
        lockingAddress = _lockedStaking;
        _pause();
    }
    
    function init(
        uint256 _managerFee, 
        uint256 _performFee,
        uint256 _platformFee,
        bool _openForPublic,
        uint256 _UPMultiplier,
        uint256 _rebalancePeriod,
        uint256 _blocksPerDay,
        uint256 _smallRatio
    ) external onlyOwner whenPaused {
        require(_managerFee <= 300, "Manager Fee cap at 3%");
        require(_performFee <= 2000, "Performance Fee cap at 20%");
        require(_platformFee <= 100, "Platform Fee cap at 1%");

        _calcFundFee();
        openForPublic = _openForPublic;
        managerFee = _managerFee;   
        UPMultiplier = _UPMultiplier;
        performFee = _performFee;
        platformFee = _platformFee;
        nextRebalance = block.number + _rebalancePeriod;
        lastFeeCollection = block.number;
        rebalanceCycle = _rebalancePeriod;
        blocksPerDay = _blocksPerDay;
        smallRatio = _smallRatio;
        _unpause();
    }
    
    function collectFundFee() external {
        _calcFundFee();
        uint256 toAward = pendingMFee;
        pendingMFee = 0;
        _mint(managerAddr, toAward);
        emitEvent.FeeEvent("managefee", address(this), toAward);
    }

    function collectPlatformFee() external {
        _calcFundFee();
        uint256 toAward = pendingPFee;
        pendingPFee = 0;
        _mint(platformWallet, toAward);
        emitEvent.FeeEvent("platformfee", address(this), toAward);
    }

    function _calcFundFee() internal {
        uint256 totalblock = block.number - lastFeeCollection;
        lastFeeCollection = block.number;
        uint256 supply = getFundTotalSupply();

        if(supply == 0) return;

        // calculate number of shares to create per block
        uint256 uPerBlock = supply * 10000 / (10000 - managerFee);
        uPerBlock = uPerBlock - supply; // total new blocks generated in a year

        // calculate number of shares to create per block for platform
        uint256 uPerBlockPlatform = supply * 10000 / (10000 - platformFee);
        uPerBlockPlatform = uPerBlockPlatform - supply; // total new blocks generated in a year

        // award the shares
        pendingMFee += (totalblock * uPerBlock) / (blocksPerDay * 365);
        pendingPFee += (totalblock * uPerBlockPlatform) / (blocksPerDay * 365);
    }
 
    /// @dev return number of target names
    function createTargetNames(address[] calldata _toAddr,  uint256[] calldata _targets) public onlyRebManager {
        require(_toAddr.length > 0, "At least one target is required");
        require(_toAddr.length == _targets.length, "in array lengths mismatch");
        require(!findDup(_toAddr), "Duplicate found in targetArray");
        uint256 sum = sumArray(_targets);
        require(sum == 10000, "xWinFundV2: Sum must equal 100%");
        if (targetAddr.length > 0) {
            for (uint256 i = 0; i < targetAddr.length; i++) {
                TargetWeight[targetAddr[i]] = 0;
            }
            delete targetAddr;
        }
        
        for (uint256 i = 0; i < _toAddr.length; i++) {
            _getLatestPrice(_toAddr[i]); // ensures that the address provided is supported
            TargetWeight[_toAddr[i]] = _targets[i];
            targetAddr.push(_toAddr[i]);
        }
    }
    
    /// @dev perform rebalance with new weight and reset next rebalance period
    function Rebalance(
        address[] calldata _toAddr, 
        uint256[] calldata _targets,
        uint32 _slippage
    ) public onlyRebManager {
        
        xWinLib.DeletedNames[] memory deletedNames = _getDeleteNames(_toAddr);
        for (uint256 x = 0; x < deletedNames.length; x++){
            if(deletedNames[x].token != address(0)){
                  _moveNonIndex(deletedNames[x].token, _slippage);
            }
            if (deletedNames[x].token == baseToken) {
                baseTokenAmt = 0;
            }
        }
        createTargetNames(_toAddr, _targets);        
        _rebalance(_slippage);
    }

    function Rebalance(
        address[] calldata _toAddr, 
        uint256[] calldata _targets
    ) external onlyRebManager {
        Rebalance(_toAddr, _targets, 0);
    }
    
    /// @dev perform subscription based on ratio setup
    function deposit(uint256 amount, uint32 _slippage) public whenNotPaused returns (uint256) {
        require(targetAddr.length > 0, "xWinFundV2: This fund is empty");
        
        if(!openForPublic){
            require(validInvestors[msg.sender], "not valid wallet to deposit");
        }
        // manager fee calculation
        _calcFundFee();
        uint256 unitPrice = _getUnitPrice();
        
        // collect deposit and swap into asset
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), amount);


        if(nextRebalance < block.number){
            _rebalance(_slippage);
        }else{            
            uint256 total = getBalance(baseToken);
            total -= baseTokenAmt; // subtract baseTokenAmt
            for (uint256 i = 0; i < targetAddr.length; i++) {
                uint256 proposalQty = getTargetWeightQty(targetAddr[i], total);
                if(proposalQty > 0){
                    IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(xWinSwap), proposalQty);
                    xWinSwap.swapTokenToToken(proposalQty, baseToken, targetAddr[i], _slippage);
                }
                if (targetAddr[i] == baseToken) {
                    baseTokenAmt += proposalQty;
                }
            }
        }

        // mint and log user data
        uint256 mintQty = _getMintQty(unitPrice);
        _mint(msg.sender, mintQty);
        setPerformDeposit(mintQty, unitPrice);


        emitEvent.FundEvent("deposit", address(this), msg.sender, _convertTo18(unitPrice, baseToken), amount, mintQty);
        return mintQty;
    }

    function deposit(uint256 amount) external override whenNotPaused returns (uint256) {
        return deposit(amount, 0);
    }
    
    /// @dev perform redemption based on unit redeem
    function withdraw(uint256 amount, uint32 _slippage) public whenNotPaused returns (uint256){
        
        require(IERC20Upgradeable(address(this)).balanceOf(msg.sender) >= amount, "no balance to withdraw");

        _calcFundFee();
        uint256 unitP = _getUnitPrice();
        uint256 redeemratio = amount * 1e18 / getFundTotalSupply();
        _burn(msg.sender, amount);
        
	    uint256 totalBase = getBalance(baseToken) - baseTokenAmt;
        uint256 entitled = redeemratio * totalBase / 1e18;
        uint256 remained = totalBase - entitled;
        
        for (uint256 i = 0; i < targetAddr.length; i++) {
            xWinLib.transferData memory _transferData = _getTransferAmt(targetAddr[i], redeemratio);
            if(_transferData.totalTrfAmt > 0) {
                IERC20Upgradeable(targetAddr[i]).safeIncreaseAllowance(address(xWinSwap), _transferData.totalTrfAmt);
                xWinSwap.swapTokenToToken(_transferData.totalTrfAmt, targetAddr[i], baseToken, _slippage);
            }
            if (targetAddr[i] == baseToken) {
                baseTokenAmt -= _transferData.totalTrfAmt;
            }
        }

        uint256 totalOutput = getBalance(baseToken) - baseTokenAmt - remained;
        uint256 finalOutput = setPerformWithdraw(totalOutput, amount, msg.sender, managerAddr);
        IERC20Upgradeable(baseToken).safeTransfer(msg.sender, finalOutput);
        emitEvent.FundEvent("withdraw", address(this), msg.sender, _convertTo18(unitP, baseToken), finalOutput, amount);

        return finalOutput;
    }

    function withdraw(uint256 amount) external override whenNotPaused returns (uint256){
        return withdraw(amount, 0);
    }

    
    /// @dev fund owner move any name back to BNB
    function MoveNonIndexNameToBase(address _token, uint32 _slippage) external onlyOwner 
        returns (uint256 balanceToken, uint256 swapOutput) {
            
            (balanceToken, swapOutput) = _moveNonIndex(_token, _slippage);
            return (balanceToken, swapOutput);
    }
        
        
    /// @dev get the proportional token without swapping it in emergency case
    function emergencyRedeem(uint256 redeemUnit) external whenPaused {
        uint256 redeemratio = redeemUnit * 1e18 / getFundTotalSupply();
        require(redeemratio > 0, "redeem ratio is zero");
        _burn(msg.sender, redeemUnit);
        uint256 totalOutput = redeemratio * (getBalance(baseToken) - baseTokenAmt) / 1e18;
        IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalOutput);
        
        for (uint256 i = 0; i < targetAddr.length; i++) {
            xWinLib.transferData memory _transferData = _getTransferAmt(targetAddr[i], redeemratio);
            if(_transferData.totalTrfAmt > 0){
                if (targetAddr[i] == baseToken) {
                    baseTokenAmt -= _transferData.totalTrfAmt;
                }
                IERC20Upgradeable(targetAddr[i]).safeTransfer(msg.sender, _transferData.totalTrfAmt);
            }
        }
    }
        
    /// @dev Calc return balance during redemption
    function _getTransferAmt(address underying, uint256 redeemratio) 
        internal view returns (xWinLib.transferData memory transData) {
       
        xWinLib.transferData memory _transferData;
        if (underying == baseToken) {
            _transferData.totalUnderlying = baseTokenAmt;
        } else {
            _transferData.totalUnderlying = getBalance(underying); 
        }
        uint256 qtyToTrf = redeemratio * _transferData.totalUnderlying / 1e18;
        _transferData.totalTrfAmt = qtyToTrf;
        return _transferData;
    }
    
    /// @dev Calc qty to issue during subscription 
    function _getMintQty(uint256 _unitPrice) internal view returns (uint256 mintQty)  {
        
        uint256 vaultValue = _getVaultValues();
        uint256 totalSupply = getFundTotalSupply();
        if(totalSupply == 0) return _convertTo18(vaultValue / UPMultiplier, baseToken); 
        uint256 newTotalSupply = vaultValue * 1e18 / _unitPrice;
        mintQty = newTotalSupply - totalSupply;
        return mintQty;
    }
    
    function _getActiveOverWeight(address destAddr, uint256 totalvalue) 
        internal view returns (uint256 destRebQty, uint256 destActiveWeight, bool overweight) {
        
        destRebQty = 0;
        uint256 destTargetWeight = TargetWeight[destAddr];
        uint256 destValue = _getTokenValues(destAddr);
        if (destAddr == baseToken) {
            destValue = baseTokenAmt;
        }
        uint256 fundWeight = destValue * 10000 / totalvalue;
        overweight = fundWeight > destTargetWeight;
        destActiveWeight = overweight ? fundWeight - destTargetWeight: destTargetWeight - fundWeight;
        if(overweight){
            uint256 price = _getLatestPrice(destAddr);
            destRebQty = ((destActiveWeight * totalvalue *  getDecimals(destAddr)) / price) / 10000;
        }
        return (destRebQty, destActiveWeight, overweight);
    }
    
    function _rebalance(uint32 _slippage) internal {
        
        (xWinLib.UnderWeightData[] memory underwgts, uint256 totalunderwgt) = _sellOverWeightNames(_slippage);
        _buyUnderWeightNames(underwgts, totalunderwgt, _slippage); 
        nextRebalance = block.number + rebalanceCycle;
    }
    
    function _sellOverWeightNames (uint32 _slippage) 
        internal returns (xWinLib.UnderWeightData[] memory underwgts, uint256 totalunderwgt) {
        
        uint256 totalbefore = _getVaultValues();
        underwgts = new xWinLib.UnderWeightData[](targetAddr.length);

        for (uint256 i = 0; i < targetAddr.length; i++) {
            (uint256 rebalQty, uint256 destMisWgt, bool overweight) = _getActiveOverWeight(targetAddr[i], totalbefore);
            if(overweight) //sell token to base
            {
                IERC20Upgradeable(targetAddr[i]).safeIncreaseAllowance(address(xWinSwap), rebalQty);
                xWinSwap.swapTokenToToken(rebalQty, targetAddr[i], baseToken, _slippage);
                if (targetAddr[i] == baseToken) {
                    baseTokenAmt -= rebalQty;
                }
            }else if(destMisWgt > 0)
            {
                xWinLib.UnderWeightData memory _underWgt;
                _underWgt.token = targetAddr[i];
                _underWgt.activeWeight = destMisWgt;
                underwgts[i] = _underWgt;
                totalunderwgt = totalunderwgt + destMisWgt;
            }
        }
        return (underwgts, totalunderwgt);
    }
    
    function _buyUnderWeightNames (xWinLib.UnderWeightData[] memory underweights, uint256 totalunderwgt, uint32 _slippage) 
        internal {
        uint baseccyBal = getBalance(baseToken) - baseTokenAmt;
        for (uint256 i = 0; i < underweights.length; i++) {
            
            if(underweights[i].token != address(0)){
                uint256 rebBuyQty = underweights[i].activeWeight * baseccyBal / totalunderwgt;
                if(rebBuyQty > 0 && rebBuyQty <= baseccyBal){
                    IERC20Upgradeable(baseToken).safeIncreaseAllowance(address(xWinSwap), rebBuyQty);
                    xWinSwap.swapTokenToToken(rebBuyQty, baseToken, underweights[i].token, _slippage);
                    if(underweights[i].token == baseToken) {
                        baseTokenAmt += rebBuyQty;
                    }
                }
            }
        }
    }
    
    function _moveNonIndex(
        address _token,
        uint32 _slippage
    ) internal returns (uint256 balanceToken, uint256 swapOutput) {
            
            balanceToken = getBalance(_token);
            IERC20Upgradeable(_token).safeIncreaseAllowance(address(xWinSwap), balanceToken);
            swapOutput = xWinSwap.swapTokenToToken(balanceToken, _token, baseToken, _slippage);
            return (balanceToken, swapOutput);
    }
    
    
    function _getDeleteNames(address[] calldata _toAddr) 
        internal 
        view 
        returns (xWinLib.DeletedNames[] memory delNames) 
    {
        
        delNames = new xWinLib.DeletedNames[](targetAddr.length);

        for (uint256 i = 0; i < targetAddr.length; i++) {
            uint256 matchtotal = 1;
            for (uint256 x = 0; x < _toAddr.length; x++){
                if(targetAddr[i] == _toAddr[x]){
                    break;
                }else if(targetAddr[i] != _toAddr[x] && _toAddr.length == matchtotal){
                    delNames[i].token = targetAddr[i]; 
                }
                matchtotal++;
            }
        }
        return delNames;
    }
    
    function _convertTo18(uint256 value, address token) internal view returns (uint){
        uint256 diffDecimal = 18 - ERC20Upgradeable(token).decimals();
        return diffDecimal > 0 ? (value * (10**diffDecimal)) : value; 
    }

    /// @dev display estimate shares if deposit 
    function getEstimateShares(uint256 _amt) external view returns (uint256 mintQty)  {
        
        uint _unitPrice = _getUnitPrice();
        uint256 vaultValue = _getVaultValues() + _amt;
        uint256 totalSupply = getFundTotalSupply();
        uint256 newTotalSupply = vaultValue * 1e18 / _unitPrice;
        mintQty = newTotalSupply - totalSupply;
    }
    
    /// @dev return unit price
    function getUnitPrice() override external view returns(uint256){
        return _getUP();
    }

    function _getUnitPrice(uint256 fundvalue) internal view returns(uint256){
        return getFundTotalSupply() == 0 ? UPMultiplier * 1e18 : _convertTo18(fundvalue *  1e18 / getFundTotalSupply(), baseToken);
    }

    /// @dev return unit price in USd
    function getUnitPriceInUSD() override external view returns(uint256){
        return _getUPInUSD();
    }
    
    function getLatestPrice(address _targetAdd) external view returns (uint256) {
        return _getLatestPrice(_targetAdd);
    }

    function getVaultValues() external override view returns (uint) {
        return _convertTo18(_getVaultValues(), baseToken);
    }

    function getVaultValuesInUSD() external override view returns (uint) {
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }  

    /// @dev return token value in the vault in BNB
    function getTokenValues(address tokenaddress) external view returns (uint256){
        return _convertTo18(_getTokenValues(tokenaddress), baseToken);
    }

    // get fund total supply including fees
    function getFundTotalSupply() public view returns(uint256) {
        return totalSupply() + pendingMFee + pendingPFee;
    }


    function _getLatestPrice(address _targetAdd) internal view returns (uint256) {
        if(_targetAdd == baseToken) return getDecimals(baseToken);
        uint256 rate = priceMaster.getPrice(_targetAdd, baseToken);
        return rate;
    }

    function _getLatestPriceInUSD(address _targetAdd) internal view returns (uint256) {
        if(_targetAdd == stablecoinUSDAddr) return getDecimals(stablecoinUSDAddr);
        uint256 rate = priceMaster.getPrice(_targetAdd, stablecoinUSDAddr);
        return rate;
    }
    
    function _getVaultValues() internal override view returns (uint256){
        
        uint256 totalValue = _getTokenValues(baseToken);
        for (uint256 i = 0; i < targetAddr.length; i++) {
            if(targetAddr[i] == baseToken) {
                continue;
            }
            totalValue = totalValue + _getTokenValues(targetAddr[i]);
        }
        return totalValue; 
    }

    function _getVaultValuesInUSD() internal view returns (uint256){
        
        uint256 totalValue = _getTokenValuesInUSD(baseToken);
        for (uint256 i = 0; i < targetAddr.length; i++) {
            if(targetAddr[i] == baseToken) {
                continue;
            }
            totalValue = totalValue + _getTokenValuesInUSD(targetAddr[i]);
        }
        return totalValue; 
    }

    function _getUP() internal view returns(uint256){
        return getFundTotalSupply() == 0 ? UPMultiplier * 1e18 : _convertTo18(_getVaultValues() *  1e18 / getFundTotalSupply(), baseToken);
    }

    function _getUnitPrice() internal override view returns(uint256){
        return getFundTotalSupply() == 0 ? UPMultiplier * 1e18 : _getVaultValues() *  1e18 / getFundTotalSupply();
    }

    function _getUPInUSD() internal view returns(uint256){
        return getFundTotalSupply() == 0 ? UPMultiplier * 1e18 : _convertTo18(_getVaultValuesInUSD() * 1e18 / getFundTotalSupply(), stablecoinUSDAddr);
    }

    function _getTokenValues(address token) internal view returns (uint256){
        uint256 tokenBalance = getBalance(token);
        uint256 price = _getLatestPrice(token);
        return tokenBalance * uint256(price) / getDecimals(token); 
    }

    function _getTokenValuesInUSD(address token) internal view returns (uint256){
        
        uint256 tokenBalance = getBalance(token);
        uint256 price = _getLatestPriceInUSD(token);
        return tokenBalance * uint256(price) / getDecimals(token);
    }

    function getBalance(address fromAdd) public view returns (uint256){
        return IERC20Upgradeable(fromAdd).balanceOf(address(this));
    }

    function getTargetNamesAddress() external view returns (address[] memory _targetNamesAddress){
        return targetAddr;
    }

    /// @dev return target amount based on weight of each token in the fund
    function getTargetWeightQty(address targetAdd, uint256 srcQty) internal view returns (uint256){
        return TargetWeight[targetAdd] * srcQty / 10000;
    }
    
    /// Get All the fund data needed for client
    function GetFundExtra() external view returns (
          uint256 managementFee,
          uint256 performanceFee,
          uint256 platFee,
          address mAddr,          
          address mRebAddr,   
          address pWallet       
        ){
            return (
                managerFee,
                performFee,
                platformFee,
                managerAddr, 
                managerRebAddr,
                platformWallet
            );
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

    /// Get All the fund data needed for client
    function GetFundDataAll() external view returns (
          IERC20Upgradeable baseCcy,
          address[] memory targetAddress,
          uint256 totalUnitB4,
          uint256 baseBalance,
          uint256 unitprice,
          uint256 fundvalue,
          uint256 unitpriceUSD,
          uint256 fundvalueUSD,
          string memory fundName,
          string memory symbolName 
        ){
            return (
                IERC20Upgradeable(baseToken), 
                targetAddr, 
                getFundTotalSupply(), 
                getBalance(baseToken),
                _getUP(), 
                _convertTo18(_getVaultValues(), baseToken),
                _getUPInUSD(), 
                _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr),
                name(),
                symbol()
            );
    }

    function setValidInvestor(address _wallet, bool _allow) external onlyRebManager {
        validInvestors[_wallet] = _allow;
    }

    function setOpenForPublic(bool _allow) external onlyOwner {
        openForPublic = _allow;
    }

    function updateOtherProperties(uint256 newCycle, uint256 _ratio, uint256 _UPMultiplier) external onlyOwner  {
        rebalanceCycle = newCycle;
        smallRatio = _ratio;
        UPMultiplier = _UPMultiplier;
    }

    /// @dev update average blocks per day value
    function updateBlockPerday(uint256 _blocksPerDay) external onlyOwner  {        
        blocksPerDay = _blocksPerDay;
    }

    /// @dev update platform fee and wallet
    function updatePlatformProperty(address _newAddr, uint256 _newFee) external onlyOwner {
        require(_newAddr != address(0), "_newAddr Input 0");
        require(_newFee <= 100, "Platform Fee cap at 1%");
        _calcFundFee();
        platformWallet = _newAddr;
        platformFee = _newFee;
    }

    function setPerformanceFee(uint256 _performFee) external onlyOwner {
        require(_performFee <= 2000, "Performance Fee cap at 20%");
        performFee = _performFee;
    }
    
    /// @dev update manager fee and wallet
    function updateManagerProperty(address newRebManager, address newManager, uint256 newFeebps) external onlyOwner  {
        require(newRebManager != address(0), "newRebManager Input 0");
        require(newManager != address(0), "newManager Input 0");
        require(newFeebps <= 300, "Manager Fee cap at 3%");
        _calcFundFee();
        managerFee = newFeebps;
        managerAddr = newManager;
        managerRebAddr = newRebManager;
    }
    
    /// @dev update xwin master contract
    function updatexWinEngines(address _priceMaster, address _xwinSwap) external onlyOwner {
        require(_priceMaster != address(0), "_priceMaster Input 0");
        require(_xwinSwap != address(0), "_xwinSwap Input 0");
        priceMaster = IxWinPriceMaster(_priceMaster);
        xWinSwap = IxWinSwap(_xwinSwap);
    }

    function updateLockedStakingAddress(address _lockedStaking) external onlyOwner {
        lockingAddress = _lockedStaking;
    }

    function setPerformDeposit(uint256 mintShares, uint256 latestUP) internal {
        uint256 newTotalShares = performanceMap[msg.sender].shares + mintShares;
        performanceMap[msg.sender].avgPrice = ((performanceMap[msg.sender].shares * performanceMap[msg.sender].avgPrice) + (mintShares * latestUP)) / newTotalShares;
        performanceMap[msg.sender].shares = newTotalShares;
    }

    function setPerformWithdraw(
        uint256 swapOutput, 
        uint256 _shares,
        address _investorAddress, 
        address _managerAddress
    ) internal returns (uint256) {

        uint256 realUnitprice = swapOutput * 1e18 /_shares;
        uint256 performanceUnit;
        uint256 notRecognizedShare;

        userAvgPrice memory pM = performanceMap[_investorAddress];

        if (_shares > pM.shares) {
            notRecognizedShare = _shares - pM.shares;
        }
        uint256 recognizedShare = _shares - notRecognizedShare;
        uint256 notRecognisedRatio = notRecognizedShare * 10000 / _shares;

        // if no shares recorded, then charge for performance fee on entire swap output of unrecognized tokens
        if(notRecognizedShare > 0) {
            uint256 notRecognizedWithdraw = notRecognisedRatio * swapOutput / 10000;
            performanceUnit = notRecognizedWithdraw * performFee / 10000;
        }

        uint256 profitPerUnit = realUnitprice > pM.avgPrice ? realUnitprice - pM.avgPrice : 0; 
        if(notRecognizedShare == 0 && (performFee == 0 || waivedPerformanceFees[msg.sender] || profitPerUnit == 0)){
            uint remain = pM.shares - _shares;
            performanceMap[_investorAddress].shares = remain;
            if(remain == 0 ){
                performanceMap[_investorAddress].avgPrice = 0;
            } 
            return swapOutput;
        }

        if(recognizedShare > 0) {
            uint256 actualPerformFee = getDiscountedPerformFee(msg.sender);
            performanceMap[_investorAddress].shares = pM.shares - recognizedShare;
            uint256 anotherProfit = (10000 - notRecognisedRatio) * profitPerUnit * swapOutput / realUnitprice / 10000;
            performanceUnit = performanceUnit + (anotherProfit * actualPerformFee / 10000);
        }

        if(performanceUnit > 0) IERC20Upgradeable(baseToken).safeTransfer(_managerAddress, performanceUnit);
        return swapOutput - performanceUnit;
    }


    function getUserAveragePrice(address _user) external view returns (uint256 shares, uint256 avgPrice){        
        return (performanceMap[_user].shares, performanceMap[_user].avgPrice);
    }

    function getDiscountedPerformFee(address _user) public view returns (uint256 newPerformanceFee) {
        if (lockingAddress == address(0)) {
            return performFee;
        }
        uint256 discount = ILockedStake(lockingAddress).getFavor(_user);
        return performFee - ((performFee * discount) / 10000);
    }

    function addContractWaiveFee(address _contract) external onlyOwner {
        waivedPerformanceFees[_contract] = true; 
    }

    function removeContractWaiveFee(address _contract) external onlyOwner {
        waivedPerformanceFees[_contract] = false;
    }

    function sumArray(uint256[] calldata arr) private pure returns(uint256) {
        uint256 i;
        uint256 sum = 0;
            
        for(i = 0; i < arr.length; i++)
            sum = sum + arr[i];
        return sum;
    }

    function findDup(address[] calldata a) private pure returns(bool) {
        for(uint i = 0; i < a.length - 1; i++) {
            for(uint j = i + 1; j < a.length; j++) {
                if (a[i] == a[j]) return true;
            }
        }
        return false;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    modifier onlyRebManager {
        require(
            msg.sender == managerRebAddr,
            "Only for Reb Manager"
        );
        _;
    }

}