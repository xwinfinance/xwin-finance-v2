// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinSwap.sol";
import "../Interface/IxWinStrategyInteractor.sol";
import "../xWinStrategyWithFee.sol";
import "../Interface/IxWinPriceMaster.sol";
import "../Library/xWinLib.sol";

contract xWinAllocations is xWinStrategyWithFee {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IxWinSwap public xWinSwap;
    IxWinPriceMaster public priceMaster;

    mapping(address => bool) public executors;

    mapping(address => uint256) public TargetWeight;
    address[] public targetAddr;
    uint256 private baseTokenAmt;

    function initialize(
        string memory _name,
        string memory _symbol,
        address _baseToken,
        address _swapEngine,
        address _USDTokenAddr,
        address _xWinPriceMaster,
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
        baseToken = _baseToken;
        xWinSwap = IxWinSwap(_swapEngine);
        priceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    /// @dev update xwin master contract
    function updatexWinPriceMaster(
        address _xWinPriceMaster
    ) external onlyOwner {
        priceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    function _deposit(
        uint256 _amount,
        uint32 _slippage
    ) internal returns (uint256) {
        require(_amount > 0, "Nothing to deposit");
        _calcFundFee();
        for (uint256 i = 0; i < targetAddr.length; i++) {
            if (
                IxWinStrategyInteractor(address(xWinSwap)).isxWinStrategy(
                    targetAddr[i]
                )
            ) {
                xWinStrategyWithFee(targetAddr[i]).collectFundFee();
                if (
                    xWinStrategyWithFee(targetAddr[i])
                        .canCollectPerformanceFee() &&
                    xWinStrategyWithFee(targetAddr[i]).performanceFee() > 0
                ) {
                    xWinStrategyWithFee(targetAddr[i]).collectPerformanceFee();
                }
            }
        }
        uint256 unitPrice = _getUnitPrice();

        IERC20Upgradeable(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 total = getBalance(baseToken);
        total -= baseTokenAmt; // subtract baseTokenAmt
        for (uint256 i = 0; i < targetAddr.length; i++) {
            uint256 proposalQty = getTargetWeightQty(targetAddr[i], total);
            if (proposalQty > 0) {
                IERC20Upgradeable(baseToken).safeIncreaseAllowance(
                    address(xWinSwap),
                    proposalQty
                );
                xWinSwap.swapTokenToToken(
                    proposalQty,
                    baseToken,
                    targetAddr[i],
                    _slippage
                );
            }
            if (targetAddr[i] == baseToken) {
                baseTokenAmt += proposalQty;
            }
        }

        uint256 currentShares = _calcMintQty(unitPrice);
        _mint(msg.sender, currentShares);

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "deposit",
                address(this),
                msg.sender,
                _convertTo18(unitPrice, baseToken),
                _amount,
                currentShares
            );
        }

        return currentShares;
    }

    function deposit(
        uint256 amount
    ) external override nonReentrant whenNotPaused returns (uint256) {
        return _deposit(amount, 0);
    }

    function deposit(
        uint256 _amount,
        uint32 _slippage
    ) public override nonReentrant whenNotPaused returns (uint256) {
        return _deposit(_amount, _slippage);
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
        uint256 unitP = getUnitPrice();
        uint redeemratio = (_shares * 1e18) / getFundTotalSupply();

        uint256 totalBase = getBalance(baseToken) - baseTokenAmt;
        uint256 entitled = (redeemratio * totalBase) / 1e18;
        uint256 remained = totalBase - entitled;

        for (uint256 i = 0; i < targetAddr.length; i++) {
            xWinLib.transferData memory _transferData = _getTransferAmt(
                targetAddr[i],
                redeemratio
            );
            if (_transferData.totalTrfAmt > 0) {
                IERC20Upgradeable(targetAddr[i]).safeIncreaseAllowance(
                    address(xWinSwap),
                    _transferData.totalTrfAmt
                );
                xWinSwap.swapTokenToToken(
                    _transferData.totalTrfAmt,
                    targetAddr[i],
                    baseToken,
                    _slippage
                );
            }
            if (targetAddr[i] == baseToken) {
                baseTokenAmt -= _transferData.totalTrfAmt;
            }
        }

        uint256 totalOutput = getBalance(baseToken) - baseTokenAmt - remained;
        totalOutput = performanceWithdraw(_shares, totalOutput);
        _burn(msg.sender, _shares);
        if (totalOutput > 0)
            IERC20Upgradeable(baseToken).safeTransfer(msg.sender, totalOutput);

        if (!_isContract(msg.sender)) {
            emitEvent.FundEvent(
                "withdraw",
                address(this),
                msg.sender,
                unitP,
                totalOutput,
                _shares
            );
        }
        return totalOutput;
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

    function sumArray(uint256[] calldata arr) private pure returns (uint256) {
        uint256 i;
        uint256 sum = 0;

        for (i = 0; i < arr.length; i++) sum = sum + arr[i];
        return sum;
    }

    function _getLatestPrice(
        address _targetAdd
    ) internal view returns (uint256) {
        if (_targetAdd == baseToken) return getDecimals(baseToken);
        uint256 rate = priceMaster.getPrice(_targetAdd, baseToken);
        return rate;
    }

    function _getLatestPriceInUSD(
        address _targetAdd
    ) internal view returns (uint256) {
        if (_targetAdd == stablecoinUSDAddr)
            return getDecimals(stablecoinUSDAddr);
        uint256 rate = priceMaster.getPrice(_targetAdd, stablecoinUSDAddr);
        return rate;
    }

    function getLatestPrice(
        address _targetAdd
    ) external view returns (uint256) {
        return _getLatestPrice(_targetAdd);
    }

    /// @notice Sets target token addresses and weights for the fund
    function createTargetNames(
        address[] calldata _toAddr,
        uint256[] calldata _targets
    ) public onlyExecutor {
        require(_toAddr.length > 0, "At least one target is required");
        require(_toAddr.length == _targets.length, "in array lengths mismatch");
        require(!findDup(_toAddr), "Duplicate found in targetArray");

        uint256 sum = sumArray(_targets);
        require(sum == 10000, "Targets: Sum must equal 100%");
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

    /// @notice Performs rebalance with new weight and reset next rebalance period
    function Rebalance(
        address[] calldata _toAddr,
        uint256[] calldata _targets,
        uint32 _slippage
    ) public onlyExecutor {
        xWinLib.DeletedNames[] memory deletedNames = _getDeleteNames(_toAddr);
        for (uint256 x = 0; x < deletedNames.length; x++) {
            if (deletedNames[x].token != address(0)) {
                _moveNonIndex(deletedNames[x].token, _slippage);
            }
            if (deletedNames[x].token == baseToken) {
                baseTokenAmt = 0;
            }
        }
        createTargetNames(_toAddr, _targets);
        _rebalance(_slippage);
        emitEvent.FundEvent(
            "rebalance",
            address(this),
            msg.sender,
            getUnitPrice(),
            0,
            0
        );
    }

    function _moveNonIndex(
        address _token,
        uint32 _slippage
    ) internal returns (uint256 balanceToken, uint256 swapOutput) {
        balanceToken = getBalance(_token);
        IERC20Upgradeable(_token).safeIncreaseAllowance(
            address(xWinSwap),
            balanceToken
        );
        swapOutput = xWinSwap.swapTokenToToken(
            balanceToken,
            _token,
            baseToken,
            _slippage
        );
        return (balanceToken, swapOutput);
    }

    function _getDeleteNames(
        address[] calldata _toAddr
    ) internal view returns (xWinLib.DeletedNames[] memory delNames) {
        delNames = new xWinLib.DeletedNames[](targetAddr.length);

        for (uint256 i = 0; i < targetAddr.length; i++) {
            uint256 matchtotal = 1;
            for (uint256 x = 0; x < _toAddr.length; x++) {
                if (targetAddr[i] == _toAddr[x]) {
                    break;
                } else if (
                    targetAddr[i] != _toAddr[x] && _toAddr.length == matchtotal
                ) {
                    delNames[i].token = targetAddr[i];
                }
                matchtotal++;
            }
        }
        return delNames;
    }

    /// @notice Performs rebalance with new weight and reset next rebalance period
    function Rebalance(
        address[] calldata _toAddr,
        uint256[] calldata _targets
    ) external onlyExecutor {
        Rebalance(_toAddr, _targets, 0);
    }

    function _rebalance(uint32 _slippage) internal {
        (
            xWinLib.UnderWeightData[] memory underwgts,
            uint256 totalunderwgt
        ) = _sellOverWeightNames(_slippage);
        _buyUnderWeightNames(underwgts, totalunderwgt, _slippage);
    }

    function _sellOverWeightNames(
        uint32 _slippage
    )
        internal
        returns (
            xWinLib.UnderWeightData[] memory underwgts,
            uint256 totalunderwgt
        )
    {
        uint256 totalbefore = _getVaultValues();
        underwgts = new xWinLib.UnderWeightData[](targetAddr.length);

        for (uint256 i = 0; i < targetAddr.length; i++) {
            (
                uint256 rebalQty,
                uint256 destMisWgt,
                bool overweight
            ) = _getActiveOverWeight(targetAddr[i], totalbefore);
            if (overweight) //sell token to base
            {
                IERC20Upgradeable(targetAddr[i]).safeIncreaseAllowance(
                    address(xWinSwap),
                    rebalQty
                );
                xWinSwap.swapTokenToToken(
                    rebalQty,
                    targetAddr[i],
                    baseToken,
                    _slippage
                );
                if (targetAddr[i] == baseToken) {
                    baseTokenAmt -= rebalQty;
                }
            } else if (destMisWgt > 0) {
                xWinLib.UnderWeightData memory _underWgt;
                _underWgt.token = targetAddr[i];
                _underWgt.activeWeight = destMisWgt;
                underwgts[i] = _underWgt;
                totalunderwgt = totalunderwgt + destMisWgt;
            }
        }
        return (underwgts, totalunderwgt);
    }

    function _buyUnderWeightNames(
        xWinLib.UnderWeightData[] memory underweights,
        uint256 totalunderwgt,
        uint32 _slippage
    ) internal {
        uint baseccyBal = getBalance(baseToken) - baseTokenAmt;
        for (uint256 i = 0; i < underweights.length; i++) {
            if (underweights[i].token != address(0)) {
                uint256 rebBuyQty = (underweights[i].activeWeight *
                    baseccyBal) / totalunderwgt;
                if (rebBuyQty > 0 && rebBuyQty <= baseccyBal) {
                    IERC20Upgradeable(baseToken).safeIncreaseAllowance(
                        address(xWinSwap),
                        rebBuyQty
                    );
                    xWinSwap.swapTokenToToken(
                        rebBuyQty,
                        baseToken,
                        underweights[i].token,
                        _slippage
                    );
                    if (underweights[i].token == baseToken) {
                        baseTokenAmt += rebBuyQty;
                    }
                }
            }
        }
    }

    function _getActiveOverWeight(
        address destAddr,
        uint256 totalvalue
    )
        internal
        view
        returns (uint256 destRebQty, uint256 destActiveWeight, bool overweight)
    {
        destRebQty = 0;
        uint256 destTargetWeight = TargetWeight[destAddr];
        uint256 destValue = _getTokenValues(destAddr);
        if (destAddr == baseToken) {
            destValue = baseTokenAmt;
        }
        uint256 fundWeight = (destValue * 10000) / totalvalue;
        overweight = fundWeight > destTargetWeight;
        destActiveWeight = overweight
            ? fundWeight - destTargetWeight
            : destTargetWeight - fundWeight;
        if (overweight) {
            uint256 price = _getLatestPrice(destAddr);
            destRebQty =
                ((destActiveWeight * totalvalue * getDecimals(destAddr)) /
                    price) /
                10000;
        }
        return (destRebQty, destActiveWeight, overweight);
    }

    function getTokenValues(
        address tokenaddress
    ) external view returns (uint256) {
        return _convertTo18(_getTokenValues(tokenaddress), baseToken);
    }

    function _getTokenValues(address token) internal view returns (uint256) {
        uint256 tokenBalance = getBalance(token);
        uint256 price = _getLatestPrice(token);
        return (tokenBalance * uint256(price)) / getDecimals(token);
    }

    function getBalance(address fromAdd) public view returns (uint256) {
        return IERC20Upgradeable(fromAdd).balanceOf(address(this));
    }

    function _getTransferAmt(
        address underying,
        uint256 redeemratio
    ) internal view returns (xWinLib.transferData memory transData) {
        xWinLib.transferData memory _transferData;
        if (underying == baseToken) {
            _transferData.totalUnderlying = baseTokenAmt;
        } else {
            _transferData.totalUnderlying = getBalance(underying);
        }
        uint256 qtyToTrf = (redeemratio * _transferData.totalUnderlying) / 1e18;
        _transferData.totalTrfAmt = qtyToTrf;
        return _transferData;
    }

    function setExecutor(address _wallet, bool _allow) external onlyOwner {
        executors[_wallet] = _allow;
    }

    function getUnitPrice() public view override returns (uint256) {
        return
            getFundTotalSupply() == 0
                ? 1e18
                : _convertTo18(
                    (_getVaultValues() * 1e18) / getFundTotalSupply(),
                    baseToken
                );
    }

    function _getUnitPrice() internal view override returns (uint256) {
        return
            getFundTotalSupply() == 0
                ? getDecimals(baseToken)
                : (_getVaultValues() * 1e18) / getFundTotalSupply();
    }

    function getUnitPriceInUSD() public view override returns (uint256) {
        return
            getFundTotalSupply() == 0
                ? 1e18
                : _convertTo18(
                    (_getVaultValuesInUSD() * 1e18) / getFundTotalSupply(),
                    stablecoinUSDAddr
                );
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
        uint balance = _getTokenValues(baseToken);
        for (uint256 i = 0; i < targetAddr.length; i++) {
            if (targetAddr[i] == baseToken) {
                continue;
            }
            balance += _getTokenValues(address(targetAddr[i]));
        }
        return balance;
    }

    function getTargetWeightQty(
        address targetAdd,
        uint256 srcQty
    ) internal view returns (uint256) {
        return (TargetWeight[targetAdd] * srcQty) / 10000;
    }

    function _getTokenValuesInUSD(
        address token
    ) internal view returns (uint256) {
        uint256 tokenBalance = getBalance(token);
        uint256 price = _getLatestPriceInUSD(token);
        return (tokenBalance * uint256(price)) / getDecimals(token);
    }

    function getVaultValuesInUSD() external view override returns (uint) {
        return _convertTo18(_getVaultValuesInUSD(), stablecoinUSDAddr);
    }

    function _getVaultValuesInUSD() internal view returns (uint256) {
        uint256 totalValue = _getTokenValuesInUSD(baseToken);
        for (uint256 i = 0; i < targetAddr.length; i++) {
            if (targetAddr[i] == baseToken) {
                continue;
            }
            totalValue = totalValue + _getTokenValuesInUSD(targetAddr[i]);
        }
        return totalValue;
    }

    function getStableValues() public view returns (uint vaultValue) {
        return
            _convertTo18(
                IERC20Upgradeable(baseToken).balanceOf(address(this)),
                baseToken
            );
    }

    function getDecimals(address _token) private view returns (uint) {
        return (10 ** ERC20Upgradeable(_token).decimals());
    }

    function getTargetNamesAddress()
        external
        view
        returns (address[] memory _targetNamesAddress)
    {
        return targetAddr;
    }

    function findDup(address[] calldata a) private pure returns (bool) {
        for (uint i = 0; i < a.length - 1; i++) {
            for (uint j = i + 1; j < a.length; j++) {
                if (a[i] == a[j]) return true;
            }
        }
        return false;
    }
}
