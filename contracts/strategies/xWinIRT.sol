// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinSwap.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IxWinPriceMaster.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

//If nexttrade = true; Firebase buy or sell more
//ReadyToTrade is checked by Firebase function to see if it can check to buy or sell
//tradeType = 0 buy
//tradeType = 1 Sell
//SystemRetrade is called by Firebase every 1 hour by checking isretrade

contract xWinIRT is xWinStrategyWithFee, KeeperCompatibleInterface {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct TradeQueue {
        bool nextTrade;
        uint8 tradeType;
        bool ReadyToTrade;
        uint nextTradeBlock;
        uint AmountToBuy;
        uint AmountPerDay;
    }

    IERC20Upgradeable public targetToken; // BTC token
    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster;
    uint public stopLossPrice;
    uint public stopLossPerc;

    mapping(address => bool) public executors;
    TradeQueue public tradeQueue;

    uint public maxPerSwap; // 10k USDT per swap max //1,000 for testing
    uint public tradeCycle; // 1 hour

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
            "xWin IRT",
            "xIRT",
            _baseToken,
            _USDTokenAddr,
            _managerFee,
            _performanceFee,
            _collectionPeriod,
            _managerAddr
        );
        baseToken = _baseToken;
        targetToken = _targetToken;
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);

        maxPerSwap = 10000 * 10 ** ERC20Upgradeable(baseToken).decimals();
        tradeCycle = 1200; // 1 hour
        stopLossPerc = 1500;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    /// @dev update xwin master contract
    function updatexWinPriceMaster(
        address _xWinPriceMaster
    ) external onlyOwner {
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    function checkUpkeep(
        bytes calldata /*checkData*/
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = getTriggerStopLoss();
        performData = abi.encode(1);
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        require(getTriggerStopLoss(), "no stop loss condition found");
        TradeQueue memory updatedTrade;
        updatedTrade.nextTrade = true;
        updatedTrade.ReadyToTrade = false;
        updatedTrade.AmountPerDay = 0;
        updatedTrade.AmountToBuy = 0;
        updatedTrade.nextTradeBlock = block.number;
        updatedTrade.tradeType = 1;

        tradeQueue = updatedTrade;
        _systemTrade(1);
    }

    function getTriggerStopLoss() public view returns (bool) {
        if ((targetToken.balanceOf(address(this)) > 0) && ReadyToTrade()) {
            uint rate = xWinPriceMaster.getPrice(
                address(targetToken),
                baseToken
            );
            return rate <= stopLossPrice;
        }
        return false;
    }

    function _setStopLossBuy(uint _rate) internal {
        stopLossPrice = _rate - ((_rate * stopLossPerc) / 10000);
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

        IERC20Upgradeable(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _calcFundFee();
        // record user balance in usdt
        uint256 currentShares = _getMintQty(_amount);
        _mint(msg.sender, currentShares);

        if (
            BuyOrSell() == 0 &&
            targetToken.balanceOf(address(this)) == 0 &&
            !isReTrade()
        ) {
            tradeQueue.ReadyToTrade = true;
        }

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

        require(tr.nextTradeBlock <= block.number, "not allow to retrade yet");
        if (tr.AmountToBuy >= 0 && tr.AmountPerDay == 0) {
            tradeQueue.AmountPerDay = tr.AmountToBuy;
        }

        _systemTrade(tr.tradeType);
    }

    /**
     * @notice Triggered offchain when there is a signal buy or close-buy
     */
    function systemTrade(uint8 _tradeType) public onlyExecutor nonReentrant {
        require(_tradeType >= 0 && _tradeType <= 1, "tradetype out of bound");
        require(getVaultValues() > 0, "Nothing To Trade");
        require(ReadyToTrade(), "Not Ready To Trade");
        //Find Balance of StableCoin
        //Set AmountToBuy to the balance of stableCoin
        tradeQueue.tradeType = _tradeType;
        tradeQueue.ReadyToTrade = false;
        if (_tradeType == 0) {
            tradeQueue.AmountToBuy = IERC20Upgradeable(baseToken).balanceOf(
                address(this)
            );
            tradeQueue.AmountPerDay = tradeQueue.AmountToBuy / 2;
            tradeQueue.nextTrade = true;
        }

        _systemTrade(_tradeType);
    }

    function _systemTrade(uint8 _tradeType) internal {
        uint unitprice = getUnitPrice();
        // 0 = BUY, 1 = Close BUY
        if (_tradeType == 0) {
            uint amtToSwap = tradeQueue.AmountPerDay > maxPerSwap
                ? maxPerSwap
                : tradeQueue.AmountPerDay;
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
            tradeQueue.AmountToBuy = tradeQueue.AmountToBuy - amtToSwap;
            tradeQueue.AmountPerDay = tradeQueue.AmountPerDay - amtToSwap;

            if (tradeQueue.AmountPerDay == 0 && tradeQueue.AmountToBuy > 0) {
                tradeQueue.nextTradeBlock = block.number + (tradeCycle * 12);
            } else {
                tradeQueue.nextTradeBlock = block.number + tradeCycle;
            }

            if (tradeQueue.AmountToBuy == 0 && tradeQueue.AmountPerDay == 0) {
                //End of Buy
                tradeQueue.nextTradeBlock = block.number;
                tradeQueue.nextTrade = false;
                tradeQueue.ReadyToTrade = true;
                tradeQueue.tradeType = 1;
            }
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
            if (targetbal == 0) {
                tradeQueue.tradeType = 0;
                tradeQueue.ReadyToTrade = true;
            }

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

    function getVaultValues() public view override returns (uint vaultValue) {
        return getVaultValuesInUSD();
    }

    function _getVaultValues()
        internal
        view
        override
        returns (uint vaultValue)
    {
        uint stableBal = IERC20Upgradeable(baseToken).balanceOf(address(this));
        uint targetBal = targetToken.balanceOf(address(this));
        uint rate = xWinPriceMaster.getPrice(address(targetToken), baseToken);
        uint targetInBase = (targetBal * rate) /
            getDecimals(address(targetToken));
        return stableBal + targetInBase;
    }

    function getVaultValuesInUSD()
        public
        view
        override
        returns (uint vaultValue)
    {
        return _convertTo18(_getVaultValues(), stablecoinUSDAddr);
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
        TradeQueue memory tr = tradeQueue;
        //User Withdraws All In A Buy Phase
        if (
            IERC20Upgradeable(baseToken).balanceOf(address(this)) == 0 &&
            tr.tradeType == 0
        ) {
            tr.nextTrade = false;
            tr.ReadyToTrade = false;
            tr.AmountPerDay = 0;
            tr.AmountToBuy = 0;
            tr.nextTradeBlock = block.number;
            //Still have some target to do sell
            if (targetToken.balanceOf(address(this)) > 0) {
                tr.ReadyToTrade = true;
                tr.tradeType = 1;
            }
        }
        //User Withdraws All But Needs to Sell
        if (targetToken.balanceOf(address(this)) == 0 && tr.tradeType == 1) {
            tr.nextTrade = false;
            tr.ReadyToTrade = false;
            tr.nextTradeBlock = block.number;
            tr.tradeType = 0;
        }
        tradeQueue = tr;

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
        TradeQueue memory updatedTrade;
        updatedTrade.nextTrade = false;
        updatedTrade.ReadyToTrade = false;
        updatedTrade.nextTradeBlock = block.number;
        updatedTrade.tradeType = 0;
        updatedTrade.AmountPerDay = 0;
        updatedTrade.AmountToBuy = 0;
        tradeQueue = updatedTrade;
    }

    function setProperties(
        uint _tradeCycle,
        uint _maxPerSwap
    ) public onlyOwner {
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

    function setStopLossPerc(uint256 _newStopLossPerc) external onlyOwner {
        stopLossPerc = _newStopLossPerc;
    }

    /**
     * @notice Calculates the price per share
     */
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

    function GetAmountPerDay() external view returns (uint) {
        return tradeQueue.AmountPerDay;
    }

    function GetAmountToBuy() external view returns (uint) {
        return tradeQueue.AmountToBuy;
    }

    function BuyOrSell() public view returns (uint) {
        return tradeQueue.tradeType;
    }

    function ReadyToTrade() public view returns (bool) {
        return tradeQueue.ReadyToTrade;
    }

    function UserShares() external view returns (uint) {
        return IERC20Upgradeable(address(this)).balanceOf(msg.sender);
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

    function isReTrade() public view returns (bool) {
        TradeQueue memory tr = tradeQueue;
        return tr.nextTrade && tr.nextTradeBlock <= block.number;
    }
}
