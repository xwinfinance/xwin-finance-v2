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
    ) external initializer {
        __xWinStrategyWithFee_init(
            _name,
            _symbol,
            _baseToken,
            _USDTokenAddr,
            _managerFee,
            _performanceFee,
            _collectionPeriod,
            _managerAddr
        );
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
        uint256 up = _getUnitPrice();
        IERC20Upgradeable(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // record user balance in usdt
        uint currentShares = _calcMintQty(up);
        _mint(msg.sender, currentShares);

        totalDeposit = totalDeposit + _amount;

        // remaining into stablecoin
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(
            address(_baseTokenStaking),
            _amount
        );
        IxWinSingleAssetInterface(address(_baseTokenStaking)).deposit(
            _amount,
            _slippage
        );

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "deposit",
                address(this),
                msg.sender,
                _convertTo18(up, baseToken),
                _amount,
                currentShares
            );
        }
        return currentShares;
    }

    function canSystemDeposit() external view returns (bool) {
        uint amtToSwap = getAmountToSwap();
        return
            ((block.number - lastInvestedBlock) > reinvestDuration) &&
            (amtToSwap > 0);
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

    /**
     * @notice Swaps interest received from baseTokenStaking into target token
     * @dev Only possible when contract not paused.
     */
    function systemDeposit() external onlyExecutor nonReentrant {
        require(
            (block.number - lastInvestedBlock) > reinvestDuration,
            "wait till next reinvest cycle"
        );

        uint amtToSwap = getAmountToSwap();
        if (amtToSwap > 0) {
            uint earnedInterest = IxWinSingleAssetInterface(
                address(_baseTokenStaking)
            ).withdraw(amtToSwap);
            IERC20Upgradeable(baseToken).safeIncreaseAllowance(
                address(swapEngine),
                earnedInterest
            );
            swapEngine.swapTokenToToken(
                earnedInterest,
                baseToken,
                address(targetToken)
            );
            lastInvestedBlock = block.number;
        }
    }

    function getAmountToSwap() public view returns (uint) {
        // total stable coin staked in the single asset
        uint unitOwn = _baseTokenStaking.balanceOf(address(this));
        uint uprice = xWinPriceMaster.getPrice(
            address(_baseTokenStaking),
            baseToken
        );
        uint olaStableBal = (uprice * unitOwn) / 1e18;
        uint tobeinvestInAmount = olaStableBal > totalDeposit
            ? olaStableBal - totalDeposit
            : 0;
        uint tobeinvestInUnit = (tobeinvestInAmount * 1e18) / uprice;
        return tobeinvestInUnit;
    }

    function getVaultValues() public view override returns (uint vaultValue) {
        return _convertTo18(_getVaultValues(), baseToken);
    }

    function _getVaultValues()
        internal
        view
        override
        returns (uint vaultValue)
    {
        uint valueInUSD = _getVaultValuesInUSD();
        uint rate = xWinPriceMaster.getPrice(stablecoinUSDAddr, baseToken);
        return ((rate * valueInUSD) / getDecimals(address(stablecoinUSDAddr)));
    }

    function getVaultValuesInUSD()
        public
        view
        override
        returns (uint vaultValue)
    {
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }

    function _getVaultValuesInUSD() internal view returns (uint vaultValue) {
        uint exRateTargetBase = xWinPriceMaster.getPrice(
            baseToken,
            stablecoinUSDAddr
        );
        uint baseBal = IERC20Upgradeable(baseToken).balanceOf(address(this)); //ada
        uint baseBalUSD = (exRateTargetBase * baseBal) / getDecimals(baseToken); //ada in usd

        uint baseStakingUSD = 0;
        if (baseToken != address(_baseTokenStaking)) {
            uint baseStakingBal = _baseTokenStaking.balanceOf(address(this));
            uint baseStakingUP = xWinPriceMaster.getPrice(
                address(_baseTokenStaking),
                stablecoinUSDAddr
            );
            baseStakingUSD =
                (baseStakingBal * baseStakingUP) /
                getDecimals(address(_baseTokenStaking));
        }

        uint targetStakingBal = targetToken.balanceOf(address(this));
        uint targetStakingUP = xWinPriceMaster.getPrice(
            address(targetToken),
            stablecoinUSDAddr
        );
        uint targetStakingUSD = (targetStakingBal * targetStakingUP) /
            getDecimals(address(targetToken));
        return baseBalUSD + baseStakingUSD + targetStakingUSD;
    }

    function getStableValues() external view returns (uint vaultValue) {
        return
            (IxWinSingleAssetInterface(address(_baseTokenStaking))
                .getUnitPriceInUSD() *
                IxWinSingleAssetInterface(address(_baseTokenStaking))
                    .getUserBalance(address(this))) / 1e18;
    }

    function getTargetValues() external view returns (uint vaultValue) {
        return
            (xWinPriceMaster.getPrice(address(targetToken), stablecoinUSDAddr) *
                targetToken.balanceOf(address(this))) /
            getDecimals(address(targetToken));
    }

    function getBaseValues() external view returns (uint vaultValue) {
        return
            _convertTo18(
                IERC20Upgradeable(baseToken).balanceOf(address(this)),
                baseToken
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
            "Withdraw exceeds balance"
        );
        _calcFundFee();
        uint stableBalB4 = IERC20Upgradeable(baseToken).balanceOf(
            address(this)
        );
        uint redeemratio = (_shares * 1e18) / getFundTotalSupply();
        uint totalRefund = (stableBalB4 * redeemratio) / 1e18;
        totalDeposit = totalDeposit - ((totalDeposit * redeemratio) / 1e18);
        uint totalTargetTokenShares = targetToken.balanceOf(address(this));
        uint totalBaseShares = _baseTokenStaking.balanceOf(address(this));

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
            uint targetOut = swapEngine.swapTokenToToken(
                withdrawShares,
                address(targetToken),
                baseToken,
                _slippage
            );
            totalRefund += targetOut;
        }
        if (totalBaseShares > 0) {
            withdrawShares = (redeemratio * totalBaseShares) / 1e18;
            withdrawShares = totalBaseShares < withdrawShares
                ? totalBaseShares
                : withdrawShares;
            uint stableOut = IxWinSingleAssetInterface(
                address(_baseTokenStaking)
            ).withdraw(withdrawShares, _slippage);
            totalRefund += stableOut;
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

    function adminStakeStable() external onlyOwner {
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(
            address(_baseTokenStaking),
            IERC20Upgradeable(baseToken).balanceOf(address(this))
        );
        IxWinSingleAssetInterface(address(_baseTokenStaking)).deposit(
            IERC20Upgradeable(baseToken).balanceOf(address(this))
        );
    }

    function emergencyUnWindPosition() external whenPaused onlyOwner {
        uint totalTargetTokenShares = targetToken.balanceOf(address(this));
        uint totalBaseShares = _baseTokenStaking.balanceOf(address(this));
        if (totalTargetTokenShares > 0) {
            targetToken.safeIncreaseAllowance(
                address(swapEngine),
                totalTargetTokenShares
            );
            swapEngine.swapTokenToToken(
                totalTargetTokenShares,
                address(targetToken),
                baseToken
            );
        }
        if (totalBaseShares > 0) {
            IxWinSingleAssetInterface(address(_baseTokenStaking)).withdraw(
                totalBaseShares
            );
        }
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner {
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function setProperties(uint _reinvestDuration) external onlyOwner {
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
        return _convertTo18(_getUnitPrice(), baseToken);
    }

    function _getUnitPrice() internal view override returns (uint256) {
        uint vValue = _getVaultValues();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? getDecimals(baseToken)
                : (vValue * 1e18) / getFundTotalSupply();
    }

    function getUnitPriceInUSD() public view override returns (uint256) {
        uint vValue = getVaultValuesInUSD();
        return
            (getFundTotalSupply() == 0 || vValue == 0)
                ? 1e18
                : (vValue * 1e18) / getFundTotalSupply();
    }

    function getNextInvestBlock() external view returns (uint256) {
        return lastInvestedBlock + reinvestDuration;
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }
}
