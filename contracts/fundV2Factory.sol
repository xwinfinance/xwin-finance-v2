// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "./Interface/IxWinPriceMaster.sol";
import "./Interface/IFundV2.sol";
import "./Interface/IxWinStrategyInteractor.sol";
import "./Interface/IxWinEmitEvent.sol";
import "./Interface/IxWinStrategy.sol";


interface FundV2Initialize {
    function initialize(
    string calldata _name,
    string calldata _symbol,
    address _USDAddr,
    address _manageraddr,
    address _managerRebaddr,
    address _platformWallet
    ) external;

}

contract FundV2Factory is Initializable, OwnableUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    address[] public fundV2Array;
    mapping(address => bool) public supportedBaseTokens;
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public fundIDs;
    
    IERC20Upgradeable public xWinToken;
    IxWinPriceMaster public xWinPriceMaster;
    IxWinEmitEvent public xEmitEvent;

    address public beaconContract;
    address public autoLockAddr;
    address public xWinSwapAddr;
    address public xWinAdminWallet;

    address public DEFAULT_BASETOKEN;
    address public DEFAULT_MANAGER;
    address public DEFAULT_PLATFORM;
    uint256 public DEFAULT_MANAGER_FEE;
    uint256 public DEFAULT_PERFORMANCE_FEE;
    uint256 public DEFAULT_CREATION_FEE;
    uint256 public DEFAULT_PLATFORM_FEE;
    uint256 public DEFAULT_REBALANCE_PERIOD;
    uint256 public DEFAULT_BLOCKSPERDAY;
    uint256 public DEFAULT_SMALLRATIO;

    event BaseTokenUpdate(address, bool);
    event Received(address, uint256);
    event FundCreation(address rebalanceOwner, address newFund, uint256 fundId, string name, string symbol);
    
    function initialize (
        address _xWinAdminWallet,
        address _xWinSwapAddr,
        address _xWinPriceMaster,
        address _emitEventAddr,
        address _xWinLockStaking,
        address _xwinAddr,
        address _beaconAddress,
        address _baseToken,
        address _defaultManagerAddr,
        address _defaultPlatformAddr
    ) public initializer {
        __Ownable_init();
        xWinAdminWallet = _xWinAdminWallet;
        xWinSwapAddr = _xWinSwapAddr;
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
        xEmitEvent = IxWinEmitEvent(_emitEventAddr);
        autoLockAddr = _xWinLockStaking;
        xWinToken = IERC20Upgradeable(_xwinAddr);
        beaconContract = _beaconAddress;
        DEFAULT_BASETOKEN = _baseToken;
        DEFAULT_MANAGER = _defaultManagerAddr;
        DEFAULT_MANAGER_FEE = 100;
        DEFAULT_PERFORMANCE_FEE = 2000;
        DEFAULT_CREATION_FEE = 50 ether;
        DEFAULT_PLATFORM = _defaultPlatformAddr;
        DEFAULT_PLATFORM_FEE = 50;
        DEFAULT_REBALANCE_PERIOD = 876000;
        DEFAULT_BLOCKSPERDAY = 28800;
        DEFAULT_SMALLRATIO = 100;
    }
    
    function createFundPrivate(
        string memory name, 
        string memory symbol,
        address[] calldata _toAddresses,  
        uint256[] calldata _targetWeight
    ) external {
        
        if(!whitelisted[msg.sender]) {
            xWinToken.safeTransferFrom(msg.sender, xWinAdminWallet, DEFAULT_CREATION_FEE); 
        }
        address fundAddr = createProxy(name, symbol, DEFAULT_BASETOKEN, address(this), address(this), DEFAULT_BASETOKEN);  // add factory as reb manager first
        fundV2Array.push(fundAddr);
        uint256 fundId = fundV2Array.length - 1;
        fundIDs[fundAddr] = fundId;
        IxWinStrategyInteractor(xWinSwapAddr).registerStrategyContract(fundAddr, DEFAULT_BASETOKEN);
        _initialiseFund(fundId, DEFAULT_MANAGER_FEE, DEFAULT_PERFORMANCE_FEE, false, 100, DEFAULT_PLATFORM);
        IFundV2(fundAddr).createTargetNames(_toAddresses, _targetWeight);
        IFundV2(fundAddr).setValidInvestor(msg.sender, true); 

        // update reb manager to user after setting initial target
        IFundV2(fundAddr).updateManagerProperty(msg.sender, DEFAULT_MANAGER, DEFAULT_MANAGER_FEE); // update back reb manager to the user
        emit FundCreation(msg.sender, fundAddr, fundId, name, symbol);
    }

    function createFund(
        string calldata name, 
        string calldata symbol,
        address _baseToken, 
        address managerFeeAddr, 
        address rebalanceAddr, 
        address _USDAddr
    ) external onlyOwner returns (uint256) {
    
        address fundAddr = createProxy(name, symbol, _baseToken, managerFeeAddr, rebalanceAddr, _USDAddr);
        fundV2Array.push(fundAddr);
        uint256 fundId = fundV2Array.length - 1;
        fundIDs[fundAddr] = fundId;
        IxWinStrategyInteractor(xWinSwapAddr).registerStrategyContract(fundAddr, _baseToken);
        return fundId;
    }

    function createProxy(
        string memory name, 
        string memory symbol,
        address _baseToken, 
        address managerFeeAddr, 
        address rebalanceAddr,
        address _USDAddr
    ) public returns (address){
        require(supportedBaseTokens[_baseToken] , "Token address not approved for base currency.");
        string memory initializerFunction = "initialize(string,string,address,address,address,address,address,address)";
        BeaconProxy newProxyInstance = new BeaconProxy(
            beaconContract,
            abi.encodeWithSignature(
                initializerFunction, 
                name, 
                symbol,
                _baseToken,
                _USDAddr,
                managerFeeAddr, 
                rebalanceAddr,
                DEFAULT_PLATFORM,
                autoLockAddr
            )
        );
        return address(newProxyInstance);
    }

    function initialiseFund (
        uint256 fundId, 
        uint256 _managerFee, 
        uint256 _performanceFee,
        bool _openForPublic,
        uint256 _unitpriceMultiplier,
        address _platformAddr
    ) external onlyOwner {
        _initialiseFund(fundId, _managerFee, _performanceFee, _openForPublic, _unitpriceMultiplier, _platformAddr);        
    }

    function _initialiseFund(
        uint256 fundId, 
        uint256 _managerFee, 
        uint256 _performanceFee,
        bool _openForPublic,
        uint256 _unitpriceMultiplier,
        address _platformAddr
    ) internal {
        IFundV2(fundV2Array[fundId]).init(_managerFee, _performanceFee, DEFAULT_PLATFORM_FEE, _openForPublic, _unitpriceMultiplier, DEFAULT_REBALANCE_PERIOD, DEFAULT_BLOCKSPERDAY, DEFAULT_SMALLRATIO);
        IFundV2(fundV2Array[fundId]).updatexWinEngines(address(xWinPriceMaster), xWinSwapAddr);
        IFundV2(fundV2Array[fundId]).setEmitEvent(address(xEmitEvent)); 
        IFundV2(fundV2Array[fundId]).updatePlatformProperty(_platformAddr, DEFAULT_PLATFORM_FEE); 
        xEmitEvent.setExecutor(fundV2Array[fundId], true);

        //register the fund for xwinswap
    }

    // Trigger this will calculate and mint the fee to the platform manager registered wallet in bulk
    function massProcessPlatformFee() external {
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            IFundV2(fundV2Array[i]).collectPlatformFee();
        }
    }

    // Trigger this will calculate and mint the fee to the platform manager registered wallet
    function processPlatformFee(address _fundAddr) external {
        uint256 fundId = fundIDs[_fundAddr];
        IFundV2(fundV2Array[fundId]).collectPlatformFee();
    }

    // Trigger this will calculate and mint the fee to the fund manager registered wallet
    function processManagerFee(address _fundAddr) external {        
        uint256 fundId = fundIDs[_fundAddr];
        IFundV2(fundV2Array[fundId]).collectFundFee();
    }

    // Trigger this will calculate and mint the fee to the fund manager registered wallet in bulk
    function massProcessManagerFee() external {
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            IFundV2(fundV2Array[i]).collectFundFee();
        }
    }

    function setSwapAddr(address _xWinSwapAddr) external onlyOwner {
        require(_xWinSwapAddr != address(0), "_xWinSwapAddr input is 0");
        xWinSwapAddr = _xWinSwapAddr;
    }

    function addNewBaseToken(address _newTokenAddr) external onlyOwner {
        supportedBaseTokens[_newTokenAddr] = true;
        emit BaseTokenUpdate(_newTokenAddr, true);
    }

    function removeBaseToken(address _tokenAddr) external onlyOwner {
        supportedBaseTokens[_tokenAddr] = false;
        emit BaseTokenUpdate(_tokenAddr, false);
    }

    function updatePriceMaster(address _newPriceMaster) external onlyOwner {
        require(_newPriceMaster != address(0), "_newPriceMaster input is 0");
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function getLatestFundID() public view returns (uint256) {
        return fundV2Array.length - 1;
    }

    function getFundfromIndex(uint256 _index) public view returns (address){
        return fundV2Array[_index];
    }

    function setProperties(
        address _baseToken,
        uint256 _defaultManagerFee,
        uint256 _defaultPerformFee,
        address _defaultManager,
        uint256 _defaultPlatFee,
        uint256 _defaultRebalancePeriod,
        uint256 _defaultBlockPerDays,
        uint256 _defaultSmallRatio,
        address _defaultPlatform
    ) external onlyOwner {
        require(_baseToken != address(0), "_baseToken input is 0");
        DEFAULT_BASETOKEN = _baseToken;
        DEFAULT_MANAGER_FEE = _defaultManagerFee;
        DEFAULT_PERFORMANCE_FEE = _defaultPerformFee;
        DEFAULT_MANAGER = _defaultManager;
        DEFAULT_PLATFORM_FEE = _defaultPlatFee;
        DEFAULT_REBALANCE_PERIOD = _defaultRebalancePeriod;
        DEFAULT_BLOCKSPERDAY = _defaultBlockPerDays;
        DEFAULT_SMALLRATIO = _defaultSmallRatio;
        DEFAULT_PLATFORM = _defaultPlatform;

    }

    function addWhiteList(address _addr) external onlyOwner {
        whitelisted[_addr] = true;
    }

    function removeWhiteList(address _addr) external onlyOwner {
        whitelisted[_addr] = false;
    }

    function setPause(address _fundAddr, bool _pauseVal) external onlyOwner {
        isRegistered(_fundAddr);
        if(_pauseVal) {
            IFundV2(_fundAddr).setPause();
        } else {
            IFundV2(_fundAddr).setUnPause();
        }
    }

    function MoveNonIndexNameToBase(address _fundAddr, address _tokenaddress) external returns (uint256 balanceToken, uint256 swapOutput) {
        isRegistered(_fundAddr);
        return IFundV2(_fundAddr).MoveNonIndexNameToBase(_tokenaddress);
    }

    function setOpenForPublic(address _fundAddr, bool _allow) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).setOpenForPublic(_allow);
    }

    function updateOtherProperties(address _fundAddr, uint256 newCycle, uint256 _ratio, uint256 _UPMultiplier) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updateOtherProperties(newCycle, _ratio, _UPMultiplier);
    }
    function updatePlatformProperty(address _fundAddr, address newPlatformWallet, uint256 newPlatformFee) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updatePlatformProperty(newPlatformWallet, newPlatformFee);
    }
    function setPerformanceFee(address _fundAddr, uint256 newPerformFee) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).setPerformanceFee(newPerformFee);
    }
    function updateManagerProperty(address _fundAddr, address newRebManager, address newManager, uint256 newFeebps) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updateManagerProperty(newRebManager, newManager, newFeebps);
    }
    function updateBlockPerday(address _fundAddr, uint256 _blocksPerDay) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updateBlockPerday(_blocksPerDay);
    }
    function updatexWinEngines(address _fundAddr, address _xwinPricesMaster, address _xwinSwap) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updatexWinEngines(_xwinPricesMaster, _xwinSwap);
    }

    function updateUSDAddr(address _fundAddr, address _newUSDAddr) external onlyOwner {
        isRegistered(_fundAddr);
        IFundV2(_fundAddr).updateUSDAddr(_newUSDAddr);
    }

    function updateEmitEvent(address _fundAddr) external onlyOwner {
        IFundV2(_fundAddr).setEmitEvent(address(xEmitEvent));
    }

    function updateLockedStaking(address _fundAddr) external onlyOwner {
        IFundV2(_fundAddr).updateLockedStakingAddress(autoLockAddr);
    }

    function setWaivedPerformanceFee(address _fundAddr, address _toWaive, bool _status) external onlyOwner {
        if(_status) {
            IFundV2(_fundAddr).addContractWaiveFee(_toWaive);
        } else {
            IFundV2(_fundAddr).removeContractWaiveFee(_toWaive);
        }
    }

    function setAdminWallet(address _address) external onlyOwner {
        require(_address != address(0), "_address input is 0");
        xWinAdminWallet = _address;
    }

    function setEmitEvent(address _newEmitEvent) external onlyOwner {
        require(_newEmitEvent != address(0), "_newEmitEvent input is 0");
        xEmitEvent = IxWinEmitEvent(_newEmitEvent);
    }

    function setAutoLock(address _newAutoLock) external onlyOwner {
        require(_newAutoLock != address(0), "_newAutoLock input is 0");
        autoLockAddr = _newAutoLock;
    }

    function setCreationFee(uint256 _newCreationFee) external onlyOwner {
        DEFAULT_CREATION_FEE = _newCreationFee;
    }

    function isRegistered(address _fundAddress) private view {
        uint256 i = fundIDs[_fundAddress];
        require(fundV2Array[i] == _fundAddress, "xWinAdmin: address not in array");
    }

    function countTotalFunds() external view returns (uint256 count){
        return fundV2Array.length;
    }

    function countActiveFunds() external view returns (uint256 count){
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            if (IxWinStrategyInteractor(xWinSwapAddr).isActivexWinStrategy(fundV2Array[i])) {
                count++;
            }
        }
        return count;
    }

    function countTVL() external view returns (uint256 amount){
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            amount = amount + IxWinStrategy(fundV2Array[i]).getVaultValuesInUSD();
        }
        return amount;
    }

    function countFundNumberByAddress(address _user) external view returns (uint256 count){
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            (uint256 shares, ) = IFundV2(fundV2Array[i]).getUserAveragePrice(_user);
            if (shares > 0) {
                count++;
            }
        }
        return count;
    }

    /// TODO : Get the balance of the user, not from performance collection
    function countTotalTVLByAddress(address _user) external view returns (uint256 amount) {
        for(uint256 i = 0; i < fundV2Array.length; i++) {
            (uint256 shares, ) = IFundV2(fundV2Array[i]).getUserAveragePrice(_user);
            amount = amount + (
                shares * IxWinStrategy(fundV2Array[i]).getUnitPriceInUSD() / 
                10 ** IFundV2(fundV2Array[i]).decimals()
            );
        }
        return amount;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}