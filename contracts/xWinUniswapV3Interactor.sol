// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./Interface/IxWinPriceMaster.sol";
import "./xWinStrategyInteractor.sol";

contract xWinUniSwapV3Engine is xWinStrategyInteractor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct PairInfo {
        bytes multihopPath;
        uint24 poolFee;
        bool isMultihop;
    }

    IxWinPriceMaster priceMaster;
    address routerV3;
    uint24 slippage;
    mapping(address => mapping(address => PairInfo)) swapData;
    mapping(address => bool) public executors;
    event Received(address, uint256);

    function initialize(address _router) external initializer {
        xWinStrategyInteractor.__xWinStrategyInteractor_init();
        routerV3 = _router;
        slippage = 100;
        executors[msg.sender] = true;
    }

    function addTokenPath(
        address _fromtoken,
        address _totoken,
        bytes calldata _pathData,
        uint24 _fee,
        bool _isMultihop
    ) external onlyExecutor {
        if (_isMultihop) {
            require(_pathData.length != 0, "_pathData parameter empty");
        } else {
            require(_fee != 0, "_fee parameter empty");
        }
        PairInfo memory newSwapData;
        newSwapData.isMultihop = _isMultihop;
        newSwapData.multihopPath = _pathData;
        newSwapData.poolFee = _fee;
        swapData[_fromtoken][_totoken] = newSwapData;
    }

    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken
    ) public payable returns (uint) {
        require(_amount > 0, "SwapEngine: amount swap is zero");
        require(
            _fromToken != address(0) && _toToken != address(0),
            "xWinSwap, input token is empty"
        );
        isValidCaller(msg.sender);

        if (_fromToken == _toToken) {
            return _amount;
        }
        IERC20Upgradeable(_fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        (bool isStrat, uint swapOutput) = _xWinStratSwap(
            _amount,
            _fromToken,
            _toToken
        );
        if (isStrat) {
            return swapOutput;
        } else {
            return swapWithUni(_amount, _fromToken, _toToken, msg.sender);
        }
    }

    function _xWinStratSwap(
        uint256 _amount,
        address _fromToken,
        address _toToken
    ) internal returns (bool, uint) {
        if (isxWinStrategy(_fromToken)) {
            uint output = withdrawFromStrategy(_amount, _fromToken);
            address baseToken = getStrategyBaseToken(_fromToken);
            if (baseToken != _toToken) {
                uint newAmount = swapWithUni(
                    output,
                    baseToken,
                    _toToken,
                    address(this)
                );
                output = newAmount;
            }
            IERC20Upgradeable(_toToken).safeTransfer(msg.sender, output);
            return (true, output);
        } else if (isxWinStrategy(_toToken)) {
            address baseToken = getStrategyBaseToken(_toToken);

            if (baseToken != _fromToken) {
                uint newAmount = swapWithUni(
                    _amount,
                    _fromToken,
                    baseToken,
                    address(this)
                );
                _fromToken = baseToken;
                _amount = newAmount;
            }

            IERC20Upgradeable(_fromToken).safeIncreaseAllowance(
                _toToken,
                _amount
            );
            uint output = depositToStrategy(_amount, _toToken);
            IERC20Upgradeable(_toToken).safeTransfer(msg.sender, output);
            return (true, output);
        } else {
            return (false, 0);
        }
    }

    // TODO get an AmountOutQuote deposit flash loan price manipulation
    function swapWithUni(
        uint _amount,
        address _fromToken,
        address _toToken,
        address _recipient
    ) internal returns (uint) {
        PairInfo memory paths = swapData[_fromToken][_toToken];
        uint256 decimals = 10 ** ERC20Upgradeable(_fromToken).decimals();
        uint256 price = priceMaster.getPrice(_fromToken, _toToken);
        uint256 amountOutQuote = (_amount * price) -
            (_amount * price * slippage) /
            10000;
        amountOutQuote = amountOutQuote / decimals;
        if (paths.isMultihop) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter
                .ExactInputParams({
                    path: paths.multihopPath,
                    recipient: _recipient,
                    deadline: block.timestamp,
                    amountIn: _amount,
                    amountOutMinimum: amountOutQuote //price*(99.75%)
                });
            TransferHelper.safeApprove(_fromToken, routerV3, _amount);
            return ISwapRouter(routerV3).exactInput(params);
        } else {
            require(
                paths.poolFee != 0,
                "swap path not registered for token pair"
            );
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: _fromToken,
                    tokenOut: _toToken,
                    fee: paths.poolFee,
                    recipient: _recipient,
                    deadline: block.timestamp,
                    amountIn: _amount,
                    amountOutMinimum: amountOutQuote,
                    sqrtPriceLimitX96: 0
                });
            TransferHelper.safeApprove(_fromToken, routerV3, _amount);
            return ISwapRouter(routerV3).exactInputSingle(params);
        }
    }

    //allow admin to move unncessary token inside the contract
    function adminMoveToken(address _tokenAddress) external onlyOwner {
        uint256 tokenBal = IERC20Upgradeable(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, tokenBal);
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner {
        require(_newPriceMaster != address(0), "empty address input");
        priceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function setRouter(address _newRouter) external onlyOwner {
        require(_newRouter != address(0), "empty address input");
        routerV3 = _newRouter;
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _address, bool _allow) external onlyOwner {
        executors[_address] = _allow;
    }

    function isValidCaller(address sender) private view {
        require(
            xWinStrategies[sender].baseToken > address(0),
            "xWinSwap: caller not registered"
        );
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }
}
