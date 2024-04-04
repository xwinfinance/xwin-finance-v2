// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "../Interface/IxWinSwap.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinBBMA is xWinStrategyWithFee, KeeperCompatibleInterface {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct TradeQueue {
        bool nextTrade;
        uint nextTradeBlock;
        uint8 tradeType;
    }

    IERC20Upgradeable public targetToken; // BTC token

    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster;

    mapping(address => bool) public executors;
    TradeQueue public tradeQueue;

    uint public maxPerSwap; // 10k USDT per swap max
    uint public tradeCycle; // 1 hour
    uint public stopLossPrice;
    uint public takeProfitPrice;
    uint public stopLossPerc;
    uint public takeProfitPerc;

    function initialize(
        address _baseToken,
        IERC20Upgradeable _targetToken,
        address _swapEngine,
        address _USDTokenAddr,
        address _xWinPriceMaster,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) external initializer {
        __xWinStrategyWithFee_init(
            "xWIN BBMA",
            "xBBMA",
            _baseToken,
            _USDTokenAddr,
            _managerFee,
            _performanceFee,
            _collectionPeriod,
            _managerAddr
        );
        targetToken = _targetToken;
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);

        maxPerSwap = 10000 * 10 ** ERC20Upgradeable(baseToken).decimals();
        tradeCycle = 1200; // 1 hour
        stopLossPerc = 500;
        takeProfitPerc = 2000;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    function checkUpkeep(
        bytes calldata /*checkData*/
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;
        if (getTriggerTakeProfit()) {
            upkeepNeeded = true;
            performData = abi.encode(1);
        } else if (getTriggerStopLoss()) {
            upkeepNeeded = true;
            performData = abi.encode(0);
        }
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        if (getTriggerTakeProfit()) {
            _systemTrade(1);
        } else if (getTriggerStopLoss()) {
            _systemTrade(0);
        } else {
            require(false, "Something went wrong");
        }
    }

    /// @dev update xwin master contract
    function updatexWinPriceMaster(
        address _xWinPriceMaster
    ) external onlyOwner {
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    function deposit(
        uint256 _amount
    ) external override nonReentrant whenNotPaused returns (uint256) {
        return _deposit(_amount, 0);
    }

    function deposit(
        uint256 _amount,
        uint32 _slippage
    ) public override nonReentrant whenNotPaused returns (uint256) {
        return _deposit(_amount, _slippage);
    }

    function _deposit(
        uint256 _amount,
        uint32 _slippage
    ) internal returns (uint256) {
        require(_amount > 0, "Nothing to deposit");
        _calcFundFee();
        IERC20Upgradeable(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // record user balance in usdt
        uint256 currentShares = _getMintQty(_amount);
        _mint(msg.sender, currentShares);

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "deposit",
                address(this),
                msg.sender,
                getUnitPrice(),
                _amount,
                currentShares
            );
        }
        return currentShares;
    }

    function systemReTrade() external onlyExecutor nonReentrant {
        TradeQueue memory tr = tradeQueue;
        require(
            tr.nextTrade && tr.nextTradeBlock <= block.number,
            "not allow to retrade yet"
        );

        if (tr.nextTrade) {
            _systemTrade(tr.tradeType);
        }
    }

    /**
     * @notice Triggered offchain when there is a signal buy or close-buy
     */
    function systemTrade(uint8 _tradeType) public onlyExecutor nonReentrant {
        require(_tradeType >= 0 && _tradeType <= 1, "tradetype out of bound");
        _systemTrade(_tradeType);
    }

    function _systemTrade(uint8 _tradeType) internal {
        uint stablebal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint unitprice = getUnitPrice();
        // 0 = BUY, 1 = Close BUY
        if (_tradeType == 0) {
            uint amtToSwap = stablebal > maxPerSwap ? maxPerSwap : stablebal;
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(
                address(swapEngine),
                amtToSwap
            );
            uint targetOutput = swapEngine.swapTokenToToken(
                amtToSwap,
                baseToken,
                address(targetToken)
            );
            uint rate = xWinPriceMaster.getPrice(
                address(targetToken),
                baseToken
            );
            _setStopLossBuy(rate);
            _setTakeProfitBuy(rate);
            stablebal = IERC20Upgradeable(baseToken).balanceOf(address(this));
            tradeQueue.nextTrade = stablebal != 0;
            tradeQueue.nextTradeBlock = stablebal != 0
                ? block.number + tradeCycle
                : block.number;
            tradeQueue.tradeType = _tradeType;

            emitEvent.FundEvent(
                "systemBuy",
                address(this),
                msg.sender,
                unitprice,
                amtToSwap,
                targetOutput
            );
        } else if (_tradeType == 1) {
            uint targetbal = targetToken.balanceOf(address(this));
            uint rate = xWinPriceMaster.getPrice(
                address(targetToken),
                baseToken
            );
            uint maxSwapBTC = (maxPerSwap * getDecimals(address(targetToken))) /
                rate;
            uint amtToSwap = targetbal > maxSwapBTC ? maxSwapBTC : targetbal;
            targetToken.safeIncreaseAllowance(address(swapEngine), amtToSwap);
            uint stableOutput = swapEngine.swapTokenToToken(
                amtToSwap,
                address(targetToken),
                baseToken
            );
            targetbal = targetToken.balanceOf(address(this));

            tradeQueue.nextTrade = targetbal != 0;
            tradeQueue.nextTradeBlock = targetbal != 0
                ? block.number + tradeCycle
                : block.number;
            tradeQueue.tradeType = _tradeType;
            stopLossPrice = 0;
            takeProfitPrice = 0;
            emitEvent.FundEvent(
                "systemCloseBuy",
                address(this),
                msg.sender,
                unitprice,
                amtToSwap,
                stableOutput
            );
        }
    }

    function _setStopLossBuy(uint _rate) internal {
        stopLossPrice = _rate - ((_rate * stopLossPerc) / 10000);
    }

    function _setTakeProfitBuy(uint _rate) internal {
        takeProfitPrice = _rate + ((_rate * takeProfitPerc) / 10000);
    }

    function getTriggerTakeProfit() public view returns (bool) {
        if (takeProfitPrice == 0) return false;
        uint rate = xWinPriceMaster.getPrice(address(targetToken), baseToken);
        return rate >= takeProfitPrice;
    }

    function getTriggerStopLoss() public view returns (bool) {
        if (stopLossPrice == 0) return false;
        uint rate = xWinPriceMaster.getPrice(address(targetToken), baseToken);
        return rate <= stopLossPrice;
    }

    function getVaultValues() public view override returns (uint vaultValue) {
        return getVaultValuesInUSD();
    }

    function getVaultValuesInUSD()
        public
        view
        override
        returns (uint vaultValue)
    {
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }

    function _getVaultValues()
        internal
        view
        override
        returns (uint vaultValue)
    {
        return _getVaultValuesInUSD();
    }

    function _getVaultValuesInUSD() internal view returns (uint vaultValue) {
        uint stableBal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetBal = targetToken.balanceOf(address(this));
        uint rate = xWinPriceMaster.getPrice(address(targetToken), baseToken);
        uint targetInBase = (targetBal * rate) /
            getDecimals(address(targetToken));
        return stableBal + targetInBase;
    }

    function getStableValues() public view returns (uint vaultValue) {
        return
            _convertTo18(
                IERC20Upgradeable(baseToken).balanceOf(address(this)),
                baseToken
            );
    }

    function getTargetValues() public view returns (uint vaultValue) {
        return
            _convertTo18(
                targetToken.balanceOf(address(this)),
                address(targetToken)
            );
    }

    /**
     * @notice Withdraws from funds from the Cake Vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(
        uint256 _shares
    ) external override nonReentrant whenNotPaused returns (uint256) {
        return _withdraw(_shares, 0);
    }

    function withdraw(
        uint256 _shares,
        uint32 _slippage
    ) public override nonReentrant whenNotPaused returns (uint) {
        return _withdraw(_shares, _slippage);
    }

    function _withdraw(
        uint256 _shares,
        uint32 _slippage
    ) internal returns (uint256) {
        require(_shares > 0, "Nothing to withdraw");
        require(
            _shares <= IERC20Upgradeable(address(this)).balanceOf(msg.sender),
            "Withdraw amount exceeds balance"
        );
        _calcFundFee();
        uint redeemratio = (_shares * 1e18) / getFundTotalSupply();
        uint stableBal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetBal = targetToken.balanceOf(address(this));

        uint withdrawStable;
        if (stableBal > 0) {
            withdrawStable = (redeemratio * stableBal) / 1e18;
        }
        if (targetBal > 0) {
            uint withdrawTarget = (redeemratio * targetBal) / 1e18;
            if (withdrawTarget > 0) {
                targetToken.safeIncreaseAllowance(
                    address(swapEngine),
                    withdrawTarget
                );
                uint swapOut = swapEngine.swapTokenToToken(
                    withdrawTarget,
                    address(targetToken),
                    baseToken,
                    _slippage
                );
                withdrawStable = withdrawStable + swapOut;
            }
        }
        withdrawStable = performanceWithdraw(_shares, withdrawStable);
        _burn(msg.sender, _shares);
        if (withdrawStable > 0)
            IERC20Upgradeable(baseToken).safeTransfer(
                msg.sender,
                withdrawStable
            );

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "withdraw",
                address(this),
                msg.sender,
                getUnitPrice(),
                withdrawStable,
                _shares
            );
        }
        return withdrawStable;
    }

    function emergencyUnWindPosition() external whenPaused onlyOwner {
        uint targetSwap = targetToken.balanceOf(address(this));
        if (targetSwap > 0) {
            targetToken.safeIncreaseAllowance(address(swapEngine), targetSwap);
            swapEngine.swapTokenToToken(
                targetSwap,
                address(targetToken),
                baseToken
            );
        }
        tradeQueue.nextTrade = false;
        tradeQueue.nextTradeBlock = block.number;
        tradeQueue.tradeType = 0;
    }

    function setProperties(
        uint _stopLossPerc,
        uint _takeProfitPerc,
        uint _tradeCycle,
        uint _maxPerSwap
    ) public onlyOwner {
        stopLossPerc = _stopLossPerc;
        takeProfitPerc = _takeProfitPerc;
        tradeCycle = _tradeCycle;
        maxPerSwap = _maxPerSwap;
    }

    // Support multiple wallets or address as executors
    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    function setSwapEngine(address _newSwapEngine) external onlyOwner {
        swapEngine = IxWinSwap(_newSwapEngine);
    }

    function getUnitPrice() public view override returns (uint256) {
        return _getUnitPrice();
    }

    function _getUnitPrice() internal view override returns (uint256) {
        uint vValue = getVaultValues();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? 1e18
                : (vValue * 1e18) / getFundTotalSupply();
    }

    function getUnitPriceInUSD() public view override returns (uint256) {
        uint vValue = getVaultValuesInUSD();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? 1e18
                : (vValue * 1e18) / getFundTotalSupply();
    }

    function isReTrade() public view returns (bool) {
        TradeQueue memory tr = tradeQueue;
        return tr.nextTrade && tr.nextTradeBlock <= block.number;
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20(_token).decimals());
    }
}
