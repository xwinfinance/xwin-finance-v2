// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinSingleAssetInterface.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinDCA is xWinStrategyWithFee {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public targetToken; // Cake token

    IxWinSingleAssetInterface public _baseTokenStaking;
    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster;
    mapping(address => bool) public executors;
    uint256 public lastInvestedBlock;
    uint256 public maxPerSwap;
    uint256 public swapDuration;
    uint256 public reinvestDuration;

    function initialize(
        address _baseToken,
        IERC20Upgradeable _targetToken,
        address _swapEngine,
        address _priceMaster,
        address baseTokenStaking_,
        address _USDTokenAddr,
        uint256 _managerFee,
        uint256 _performanceFee,
        uint256 _collectionPeriod,
        address _managerAddr
    ) external initializer {
        __xWinStrategyWithFee_init(
            "xWIN Dollar Average Vault",
            "xDCA",
            _baseToken,
            _USDTokenAddr,
            _managerFee,
            _performanceFee,
            _collectionPeriod,
            _managerAddr
        );
        targetToken = _targetToken;
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_priceMaster);
        _baseTokenStaking = IxWinSingleAssetInterface(baseTokenStaking_);
        lastInvestedBlock = block.number; // 28800;

        maxPerSwap =
            10000 *
            10 ** ERC20Upgradeable(baseTokenStaking_).decimals();
        swapDuration = 360 * 28800;
        reinvestDuration = 28800;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
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
        // remaining into baseToken
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(
            address(_baseTokenStaking),
            IERC20Upgradeable(baseToken).balanceOf(address(this))
        );
        _baseTokenStaking.deposit(
            IERC20Upgradeable(baseToken).balanceOf(address(this)),
            _slippage
        );

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

    /// @notice View function to get the amount of base tokens to swap into target token
    function getAmountToSwap() public view returns (uint) {
        uint baseTokenBal = getStableCoinTotalBalance();
        uint blockDiff = block.number - lastInvestedBlock;
        uint toSwapQty = (baseTokenBal * blockDiff) / swapDuration;
        return toSwapQty > maxPerSwap ? maxPerSwap : toSwapQty;
    }

    function canSystemDeposit() public view returns (bool) {
        uint amtToSwap = getAmountToSwap();
        return
            ((block.number - lastInvestedBlock) > reinvestDuration) &&
            (amtToSwap > 0);
    }

    /**
     * @notice Swaps from base token to target token
     * @dev Only possible when contract not paused.
     */
    function systemDeposit() external onlyExecutor nonReentrant returns (uint) {
        require(
            (block.number - lastInvestedBlock) > reinvestDuration,
            "wait till next reinvest cycle"
        );

        uint amtToSwap = getAmountToSwap(); // return 1e18
        _baseTokenStaking.withdraw(amtToSwap);
        // swap to targetToken
        uint stableToswap = IERC20Upgradeable(baseToken).balanceOf(
            address(this)
        );
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(
            address(swapEngine),
            stableToswap
        );
        uint targetTokenAmt = swapEngine.swapTokenToToken(
            stableToswap,
            baseToken,
            address(targetToken)
        );
        lastInvestedBlock = block.number;
        return targetTokenAmt;
    }

    function getStableCoinTotalBalance() public view returns (uint) {
        uint baseTokenBalInStaking = _baseTokenStaking.getUserBalance(
            address(this)
        );
        return baseTokenBalInStaking;
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
        return getVaultValuesInUSD();
    }

    function getVaultValuesInUSD()
        public
        view
        override
        returns (uint vaultValue)
    {
        uint usdtBal = _convertTo18(
            IERC20Upgradeable(baseToken).balanceOf(address(this)),
            baseToken
        );
        uint olaStableBal = getStableValues();
        uint olaTargetBBal = getTargetValues();
        return olaStableBal + olaTargetBBal + usdtBal;
    }

    function getStableValues() public view returns (uint vaultValue) {
        return
            (_baseTokenStaking.getUnitPriceInUSD() *
                _baseTokenStaking.getUserBalance(address(this))) / 1e18;
    }

    function getTargetValues() public view returns (uint vaultValue) {
        return
            (xWinPriceMaster.getPrice(address(targetToken), stablecoinUSDAddr) *
                targetToken.balanceOf(address(this))) / 1e18;
    }

    function getBaseValues() public view returns (uint vaultValue) {
        return
            _convertTo18(
                IERC20Upgradeable(baseToken).balanceOf(address(this)),
                baseToken
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

        uint stableBalB4 = IERC20Upgradeable(baseToken).balanceOf(
            address(this)
        );
        uint redeemratio = (_shares * 1e18) / getFundTotalSupply();
        uint totalRefund = (stableBalB4 * redeemratio) / 1e18;
        uint totalTargetTokenShares = targetToken.balanceOf(address(this));
        uint totalStablecoinShares = _baseTokenStaking.getUserBalance(
            address(this)
        );

        uint withdrawShares;

        if (totalTargetTokenShares > 0) {
            withdrawShares = (redeemratio * totalTargetTokenShares) / 1e18;
            withdrawShares = totalTargetTokenShares < withdrawShares
                ? totalTargetTokenShares
                : withdrawShares;
            targetToken.safeIncreaseAllowance(
                address(swapEngine),
                withdrawShares
            );
            uint swapOut = swapEngine.swapTokenToToken(
                withdrawShares,
                address(targetToken),
                baseToken,
                _slippage
            );
            totalRefund = totalRefund + swapOut;
        }
        if (totalStablecoinShares > 0) {
            withdrawShares = (redeemratio * totalStablecoinShares) / 1e18;
            withdrawShares = totalStablecoinShares < withdrawShares
                ? totalStablecoinShares
                : withdrawShares;
            uint stableOut = _baseTokenStaking.withdraw(
                withdrawShares,
                _slippage
            );
            totalRefund = totalRefund + stableOut;
        }

        totalRefund = performanceWithdraw(_shares, totalRefund);
        _burn(msg.sender, _shares);
        if (totalRefund > 0)
            IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalRefund);

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "withdraw",
                address(this),
                msg.sender,
                getUnitPrice(),
                totalRefund,
                _shares
            );
        }
        return totalRefund;
    }

    function emergencyUnWindPosition() external whenPaused onlyOwner {
        uint totalStablecoinShares = _baseTokenStaking.getUserBalance(
            address(this)
        );
        if (totalStablecoinShares > 0) {
            _baseTokenStaking.withdraw(totalStablecoinShares);
        }
        // swap BTCB into USDT
        uint targetSwap = targetToken.balanceOf(address(this));
        if (targetSwap > 0)
            targetToken.safeIncreaseAllowance(address(swapEngine), targetSwap);
        swapEngine.swapTokenToToken(
            targetSwap,
            address(targetToken),
            baseToken
        );
    }

    // update properties
    function updateProperties(
        uint _maxPerSwap,
        uint _swapDuration,
        uint _reinvestDuration
    ) public onlyOwner {
        maxPerSwap = _maxPerSwap;
        swapDuration = _swapDuration;
        reinvestDuration = _reinvestDuration;
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    function setSwapEngine(address _newSwapEngine) external onlyOwner {
        swapEngine = IxWinSwap(_newSwapEngine);
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

    function getNextInvestBlock() public view returns (uint256) {
        return lastInvestedBlock + reinvestDuration;
    }
}
