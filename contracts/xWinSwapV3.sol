// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./Interface/ISwapRouter.sol";
import "./Interface/AllPancakeInterface.sol";
import "./Interface/IWETH.sol";
import "./Interface/IxWinSwap.sol";
import "./xWinStrategyInteractor.sol";
import "./Interface/IxWinPriceMaster.sol";

contract xWinSwapV3 is xWinStrategyInteractor {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum SwapMethod {
        UNISWAPV2,
        UNISWAPV3,
        UNISWAPV3Multihop
    }

    struct SwapInfo {
        address router;
        address[] path;
        bytes multihopPath;
        uint24 slippage;
        uint24 poolFee;
        SwapMethod swapMethod;
    }

    event Received(address, uint256);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    mapping(address => mapping(address => SwapInfo)) public swapData;
    mapping(address => bool) public executors;
    IxWinPriceMaster priceMaster;

    function initialize() external initializer {
        xWinStrategyInteractor.__xWinStrategyInteractor_init();
        executors[msg.sender] = true;
    }

    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken
    ) external returns (uint) {
        return swapTokenToToken(_amount, _fromToken, _toToken, 0);
    }

    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken,
        uint32 _slippage
    ) public returns (uint) {
        require(_amount > 0, "Nothing to deposit");
        require(
            _fromToken != address(0) && _toToken != address(0),
            "xWinSwap, input tokens cannot be empty"
        );

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
            _toToken,
            _slippage
        );
        if (isStrat) {
            return swapOutput;
        } else {
            uint totalProceeds = internalSwap(
                _amount,
                _fromToken,
                _toToken,
                msg.sender,
                _slippage
            );
            return totalProceeds;
        }
    }

    function internalSwap(
        uint _amount,
        address _fromToken,
        address _toToken,
        address recipient,
        uint32 _slippage
    ) internal returns (uint) {
        uint amountsOut = 0;
        SwapInfo memory d = swapData[_fromToken][_toToken];
        require(d.router != address(0), "xWinSwap: token swap pair not initialised");
        uint32 slippage = _slippage > 0 ? _slippage : d.slippage;
        uint256 price = priceMaster.getPrice(_fromToken, _toToken);
        uint256 amountOutQuote = (_amount * price) - (_amount * price * slippage) / 10000;
        amountOutQuote =
            amountOutQuote /
            10 ** ERC20Upgradeable(_fromToken).decimals();

        if (d.swapMethod == SwapMethod.UNISWAPV2) {
            amountsOut = _swapV2(
                _fromToken,
                _amount,
                d.path,
                d.router,
                recipient,
                amountOutQuote
            );
        } else if (d.swapMethod == SwapMethod.UNISWAPV3) {
            amountsOut = _swapV3(
                _amount,
                _fromToken,
                _toToken,
                recipient,
                d.router,
                amountOutQuote,
                d.poolFee
            );
        } else if (d.swapMethod == SwapMethod.UNISWAPV3Multihop) {
            amountsOut = _swapV3Multihop(
                _amount,
                _fromToken,
                recipient,
                d.router,
                amountOutQuote,
                d.multihopPath
            );
        }
        return amountsOut;
    }

    function _swapV2(
        address _fromToken,
        uint amountIn,
        address[] memory path,
        address router,
        address destination,
        uint256 amountOutQuote
    ) internal returns (uint) {
        IPancakeRouter02 swapRouter = IPancakeRouter02(router);
        IERC20Upgradeable(_fromToken).safeIncreaseAllowance(router, amountIn);
        uint[] memory swapAmounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutQuote,
            path,
            destination,
            block.timestamp
        );
        return swapAmounts[swapAmounts.length - 1];
    }

    function _swapV3(
        uint _amount,
        address _fromToken,
        address _toToken,
        address _recipient,
        address routerV3,
        uint256 amountOutQuote,
        uint24 poolFee
    ) internal returns (uint) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _fromToken,
                tokenOut: _toToken,
                fee: poolFee,
                recipient: _recipient,
                amountIn: _amount,
                amountOutMinimum: amountOutQuote,
                sqrtPriceLimitX96: 0
            });
        TransferHelper.safeApprove(_fromToken, routerV3, _amount);
        return ISwapRouter(routerV3).exactInputSingle(params);
    }


    function _swapV3Multihop(
        uint256 _amount,
        address _fromToken,
        address _recipient,
        address routerV3,
        uint256 amountOutQuote,
        bytes memory multihopPath
    ) internal returns (uint) {
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: multihopPath,
                recipient: _recipient,
                amountIn: _amount,
                amountOutMinimum: amountOutQuote
            });
        TransferHelper.safeApprove(_fromToken, routerV3, _amount);
        return ISwapRouter(routerV3).exactInput(params);
    }

    function getSwapData(
        address _fromtoken,
        address _totoken
    ) external view returns (SwapInfo memory _swapInfo) {
        SwapInfo memory path = swapData[_fromtoken][_totoken];
        return path;
    }

    function addTokenPath(
        address _fromtoken,
        address _totoken,
        address _router,
        address[] calldata path,
        bytes calldata _pathData,
        uint24 _slippage,
        uint24 _fee,
        SwapMethod _swapMethod
    ) external onlyExecutor {
        require(_fromtoken != _totoken, "from and to tokens are the same");

        if (_swapMethod == SwapMethod.UNISWAPV2) {
            require(
                path[0] == _fromtoken && path[path.length - 1] == _totoken,
                "Invalid path"
            );
        } else if (_swapMethod == SwapMethod.UNISWAPV3) {
            require(_fee != 0, "fee empty");
        } else if (_swapMethod == SwapMethod.UNISWAPV3Multihop) {
            require(_pathData.length != 0, "_pathData parameter empty");
        }

        SwapInfo memory newSwapData;
        newSwapData.router = _router;
        newSwapData.path = path;
        newSwapData.multihopPath = _pathData;
        newSwapData.slippage = _slippage;
        newSwapData.poolFee = _fee;
        newSwapData.swapMethod = _swapMethod;
        swapData[_fromtoken][_totoken] = newSwapData;
    }

    // check if input tokens are xWinStrategies, if yes handle the swap and return true else return false
    function _xWinStratSwap(
        uint256 _amount,
        address _fromToken,
        address _toToken,
        uint32 _slippage
    ) internal returns (bool, uint) {
        if (isxWinStrategy(_fromToken)) {
            uint output = withdrawFromStrategy(_amount, _fromToken);
            address baseToken = getStrategyBaseToken(_fromToken);
            if (baseToken != _toToken) {
                uint newAmount = internalSwap(
                    output,
                    baseToken,
                    _toToken,
                    address(this),
                    _slippage
                );
                output = newAmount;
            }
            IERC20Upgradeable(_toToken).safeTransfer(msg.sender, output);
            return (true, output);
        } else if (isxWinStrategy(_toToken)) {
            address baseToken = getStrategyBaseToken(_toToken);

            if (baseToken != _fromToken) {
                uint newAmount = internalSwap(
                    _amount,
                    _fromToken,
                    baseToken,
                    address(this),
                    _slippage
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

    //allow admin to move unncessary token inside the contract
    function adminMoveToken(address _tokenAddress) public onlyOwner {
        uint256 tokenBal = IERC20Upgradeable(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, tokenBal);
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner {
        require(_newPriceMaster != address(0), "empty address input");
        priceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _address, bool _allow) external onlyOwner {
        executors[_address] = _allow;
    }
}
