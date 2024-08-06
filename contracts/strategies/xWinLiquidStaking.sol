pragma solidity ^0.8.0;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IWBETH.sol";
import "../Interface/IOlaFinance.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinPriceMaster.sol";
import "hardhat/console.sol";

contract xWinLiquidStaking is xWinStrategyWithFee {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IxWinSwap public swapEngine;
    IxWinPriceMaster public xWinPriceMaster;
    address public liquidStakingToken;
    OlaFinance public lendingToken;
    RainMakerForOlaLens public rainMaker;
    IERC20Upgradeable public lendingRewardToken;
    uint256 public smallRatio;
    address public referrer;
    mapping(address => bool) public executors;

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
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
    ) external initializer {
        __xWinStrategyWithFee_init(
            name,
            symbol,
            _baseToken,
            _USDTokenAddr,
            _managerFee,
            _performanceFee,
            _collectionPeriod,
            _managerAddr
        );
        swapEngine = IxWinSwap(_swapEngine);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
        smallRatio = 100;
    }

    function init(
        address _liquidStakingToken,
        address _lendingRewardToken,
        address _lendingToken,
        address _rainMaker
    ) external onlyOwner {
        liquidStakingToken = _liquidStakingToken;
        lendingRewardToken = IERC20Upgradeable(_lendingRewardToken);
        lendingToken = OlaFinance(_lendingToken);
        rainMaker = RainMakerForOlaLens(_rainMaker);
    }

    function getUnitPrice() public view override returns (uint256) {
        return _convertTo18(_getUnitPrice(), baseToken);
    }

    function _getUnitPrice() internal view override returns (uint256) {
        uint256 vValue = _getVaultValues();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? 1e18
                : (vValue * 1e18) / getFundTotalSupply();
    }

    function _getUnitPrice(uint256 fundvalue) internal view returns (uint256) {
        return
            (getFundTotalSupply() == 0 || fundvalue == 0)
                ? 1e18
                : _convertTo18(
                    (fundvalue * 1e18) / getFundTotalSupply(),
                    baseToken
                );
    }

    function getUnitPriceInUSD() public view override returns (uint256) {
        uint256 vValue = _getVaultValuesInUSD();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? 1e18
                : _convertTo18(
                    (vValue * 1e18) / getFundTotalSupply(),
                    stablecoinUSDAddr
                );
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

    function withdraw(
        uint256 _amount
    ) external override nonReentrant whenNotPaused returns (uint256) {
        return _withdraw(_amount, 0);
    }

    function withdraw(
        uint256 _amount,
        uint32 _slippage
    ) public override nonReentrant whenNotPaused returns (uint256) {
        return _withdraw(_amount, _slippage);
    }

    function _deposit(
        uint256 _amount,
        uint32 /*_slippage*/
    ) internal returns (uint256) {
        require(_amount > 0, "Nothing to deposit");
        _calcFundFee();
        uint256 unitPrice = _getUnitPrice();
        IERC20Upgradeable(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 baseBalance = IERC20Upgradeable(baseToken).balanceOf(
            address(this)
        );
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(
            address(liquidStakingToken),
            baseBalance
        );
        IWBETH(liquidStakingToken).deposit(baseBalance, referrer);

        uint256 currentShares = _calcMintQty(unitPrice);
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

    // check venus-BETH, BETH and XVS
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
        uint256 redeemratio = (_shares * 1e18) / getFundTotalSupply();

        uint256 targetBalB4 = IERC20Upgradeable(liquidStakingToken).balanceOf(
            address(this)
        );
        uint256 totalRefundLiquid = (redeemratio * targetBalB4) / 1e18;

        uint256 lendingAmount = IERC20Upgradeable(address(lendingToken))
            .balanceOf(address(this));
        uint256 withdrawLendingAmt = (redeemratio * lendingAmount) / 1e18;
        withdrawLendingAmt = lendingAmount < withdrawLendingAmt
            ? lendingAmount
            : withdrawLendingAmt;
        if (withdrawLendingAmt > 0) _removeOla(withdrawLendingAmt);
        uint256 targetBalAfter = IERC20Upgradeable(liquidStakingToken)
            .balanceOf(address(this));
        totalRefundLiquid += targetBalAfter - targetBalB4;
        IERC20Upgradeable(liquidStakingToken).safeIncreaseAllowance(
            address(swapEngine),
            totalRefundLiquid
        );
        uint256 withdrawOutput = swapEngine.swapTokenToToken(
            totalRefundLiquid,
            liquidStakingToken,
            baseToken,
            _slippage
        );
        withdrawOutput = performanceWithdraw(_shares, withdrawOutput);
        _burn(msg.sender, _shares);
        IERC20Upgradeable(baseToken).safeTransfer(msg.sender, withdrawOutput);
        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "withdraw",
                address(this),
                msg.sender,
                getUnitPrice(),
                withdrawOutput,
                _shares
            );
        }
        return withdrawOutput;
    }

    function _depositOla() internal {
        uint256 bal = IERC20Upgradeable(liquidStakingToken).balanceOf(
            address(this)
        );
        if (bal > 0) {
            IERC20Upgradeable(liquidStakingToken).safeIncreaseAllowance(
                address(lendingToken),
                bal
            );
            lendingToken.mint(bal);
        }
    }

    function _getVaultValuesInUSD() internal view returns (uint256) {
        uint256 rate = xWinPriceMaster.getPrice(baseToken, stablecoinUSDAddr);
        uint256 valueInBase = _getVaultValues();

        return (rate * valueInBase) / getDecimals(address(stablecoinUSDAddr));
    }

    function _getVaultValues() internal view override returns (uint256) {
        uint256 exRateTargetBase = xWinPriceMaster.getPrice(
            liquidStakingToken, // WBETH
            baseToken // ETH
        );
        uint256 exRateLendingBase = xWinPriceMaster.getPrice(
            address(lendingRewardToken), // XVS
            baseToken // ETH
        );

        // staking target token balance
        uint256 exchangeRateStaking = lendingToken.exchangeRateStored();
        uint256 balanceStakingToken = lendingToken.balanceOf(address(this));
        uint256 balanceStakingTokenValue = balanceStakingToken == 0
            ? 0
            : (balanceStakingToken * exchangeRateStaking * exRateTargetBase) /
                getDecimals(liquidStakingToken) /
                1e18;

        // target token balance in the contract
        uint256 liquidStakingTokenBal = IERC20Upgradeable(liquidStakingToken)
            .balanceOf(address(this)); // wBETH
        uint256 liquidStakingTokenBalValue = (exRateTargetBase *
            liquidStakingTokenBal) / getDecimals(liquidStakingToken);

        // accrueComp accumulated during staking
        uint256 accruedComp = getAccruedComp();
        uint256 accruedCompValue = (exRateLendingBase * accruedComp) /
            getDecimals(address(lendingRewardToken));

        // get baseToken balance
        uint256 baseTokenBalance = IERC20Upgradeable(baseToken).balanceOf(
            address(this)
        );
        return
            baseTokenBalance +
            balanceStakingTokenValue +
            liquidStakingTokenBalValue +
            accruedCompValue;
    }

    function getVaultValues()
        external
        view
        override
        returns (uint256 vaultValue)
    {
        return _convertTo18(_getVaultValues(), baseToken);
    }

    function getVaultValuesInUSD()
        external
        view
        override
        returns (uint256 vaultValue)
    {
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }

    function getUserBalance(address _user) public view returns (uint256) {
        return IERC20Upgradeable(address(this)).balanceOf(_user);
    }

    function getSupplyRatePerBlock() public view returns (uint256) {
        return lendingToken.supplyRatePerBlock();
    }

    function getBorrowRatePerBlock() public view returns (uint256) {
        return lendingToken.borrowRatePerBlock();
    }

    function getAccruedComp() public view returns (uint256) {
        if (address(rainMaker) == address(0)) return 0;
        return rainMaker.venusAccrued(address(this));
    }

    function canReclaimRainMaker() public view returns (bool) {
        uint256 fundValueInUSD = _getVaultValuesInUSD();
        uint256 accruedComp = getAccruedComp();
        uint256 exRateLendingBase = xWinPriceMaster.getPrice(
            address(lendingRewardToken),
            stablecoinUSDAddr
        );
        uint256 accruedCompInUSD = exRateLendingBase * accruedComp;
        uint256 percentage = (accruedCompInUSD * 10000) /
            fundValueInUSD /
            getDecimals(address(lendingRewardToken));
        return percentage > smallRatio;
    }

    function canSystemDeposit() public view returns (bool) {
        uint256 fundValue = _getVaultValues();
        if (fundValue == 0) return false;
        uint256 targetbal = IERC20Upgradeable(liquidStakingToken).balanceOf(
            address(this)
        );
        uint256 percentage = (targetbal * 10000) / fundValue;
        return percentage > smallRatio;
    }

    function systemDeposit() external {
        _depositOla();
    }

    function _removeOla(uint256 _amount) internal {
        lendingToken.redeem(_amount);
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    /// @dev update small ratio
    function updateSmallRatio(uint256 _ratio) external onlyOwner {
        smallRatio = _ratio;
    }

    function setSwapEngine(address _newSwapEngine) external onlyOwner {
        swapEngine = IxWinSwap(_newSwapEngine);
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner {
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function getDecimals(address _token) private view returns (uint256) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

    function setLendingRewardToken(address _newRewardToken) public onlyOwner {
        lendingRewardToken = IERC20Upgradeable(_newRewardToken);
    }

    function setRainMaker(address rainMaker_) public onlyOwner {
        rainMaker = RainMakerForOlaLens(rainMaker_);
    }

    function _calcMintQty(
        uint256 _unitPrice
    ) internal view returns (uint256 mintQty) {
        uint256 vaultValue = _getVaultValues();
        uint256 totalSupply = getFundTotalSupply();
        if (totalSupply == 0) return _convertTo18(vaultValue, baseToken);
        uint256 newTotalSupply = (vaultValue * 1e18) / _unitPrice;
        mintQty = newTotalSupply - totalSupply;
        return mintQty;
    }

    // swap everything back into baseToken
    function emergencyUnWindPosition() external whenPaused onlyOwner {
        uint256 lendingAmount = IERC20Upgradeable(address(lendingToken))
            .balanceOf(address(this));
        if (lendingAmount > 0) {
            _removeOla(lendingAmount);
        }
    }

    function emergencyWithdraw(uint256 _shares) external whenPaused {
        require(_shares > 0, "Nothing to withdraw");
        require(
            _shares <= IERC20Upgradeable(address(this)).balanceOf(msg.sender),
            "Withdraw amount exceeds balance"
        );
        _calcFundFee();
        uint256 redeemratio = (_shares * 1e18) / getFundTotalSupply();

        uint256 targetBalB4 = IERC20Upgradeable(liquidStakingToken).balanceOf(
            address(this)
        );
        uint256 totalRefundLiquid = (redeemratio * targetBalB4) / 1e18;

        _burn(msg.sender, _shares);
        IERC20Upgradeable(liquidStakingToken).safeTransfer(
            msg.sender,
            totalRefundLiquid
        );
    }

    function setReferrer(address _referrer) external onlyOwner {
        referrer = _referrer;
    }
}
