// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./Interface/AllPancakeInterface.sol";
import "./Interface/IWETH.sol";
import "./Interface/IxWinSwap.sol";
import "./xWinStrategyInteractor.sol";
import "./Interface/IxWinPriceMaster.sol";

contract xWinSwap is xWinStrategyInteractor {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct PathInfo {
        address fromToken;
        address toToken;
        address bestRouter;
        address[] path;
        address[] inversePath;
        uint256 slippage;
    }

    event Received(address, uint256);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "executor: wut?");
        _;
    }

    mapping(address => mapping(address => PathInfo)) public pathInfoRouter;
    mapping(address => bool) public executors;
    IxWinPriceMaster priceMaster;

    function initialize() external initializer {
        xWinStrategyInteractor.__xWinStrategyInteractor_init();
        executors[msg.sender] = true;
    }

    function _swapTokenToToken(
        uint amountIn,
        address[] memory path,
        address router,
        address destination,
        uint256 slippage
    ) internal returns (uint) {
        IPancakeRouter02 swapRouter = IPancakeRouter02(router);
        uint256 price = priceMaster.getPrice(path[0], path[path.length - 1]);
        uint256 amountOutQuote = (amountIn * price) -
            (amountIn * price * slippage) /
            10000;
        amountOutQuote =
            amountOutQuote /
            10 ** ERC20Upgradeable(path[0]).decimals();

        uint[] memory swapAmounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutQuote,
            path,
            destination,
            block.timestamp
        );
        return swapAmounts[swapAmounts.length - 1];
    }

    function _swapTokenToExactToken(
        uint amountOut,
        address[] memory path,
        address router,
        address destination,
        uint256 slippage
    ) internal returns (uint) {
        IPancakeRouter02 swapRouter = IPancakeRouter02(router);
        uint256 price = priceMaster.getPrice(path[path.length - 1], path[0]);
        uint256 amountInMax = (amountOut * price) +
            (amountOut * price * slippage) /
            10000;
        amountInMax =
            amountInMax /
            10 ** ERC20Upgradeable(path[path.length - 1]).decimals();
        uint[] memory amountOutput = swapRouter.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            destination,
            block.timestamp
        );
        return amountOutput[amountOutput.length - 1];
    }

    // TODO Do we need this?
    function swapTokenToExactToken(
        uint _amount,
        uint _exactAmount,
        address _fromToken,
        address _toToken
    ) public payable returns (uint) {
        require(_amount > 0, "Nothing to deposit");
        require(
            _fromToken != address(0) && _toToken != address(0),
            "xWinSwap, input tokens cannot be empty"
        );

        IERC20Upgradeable(_fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        (
            PathInfo memory path,
            uint tradeAmount,
            bool inverse
        ) = getProportionTradeAmount(_exactAmount, _fromToken, _toToken);

        if (tradeAmount > 0)
            IERC20Upgradeable(_fromToken).safeIncreaseAllowance(
                path.bestRouter,
                tradeAmount
            );
        if (tradeAmount > 0) {
            _swapTokenToExactToken(
                tradeAmount,
                inverse ? path.inversePath : path.path,
                path.bestRouter,
                address(this),
                path.slippage
            );
        }

        uint totalProceeds = IERC20Upgradeable(_toToken).balanceOf(
            address(this)
        );
        if (totalProceeds > 0) {
            IERC20Upgradeable(_toToken).safeTransfer(msg.sender, totalProceeds);
            IERC20Upgradeable(_fromToken).safeTransfer(
                msg.sender,
                IERC20Upgradeable(_fromToken).balanceOf(address(this))
            );
        }
        return totalProceeds;
    }

    function swapTokenToToken(
        uint _amount,
        address _fromToken,
        address _toToken
    ) public payable returns (uint) {
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
            _toToken
        );
        if (isStrat) {
            return swapOutput;
        } else {
            uint totalProceeds = internalSwap(
                _amount,
                _fromToken,
                _toToken,
                msg.sender
            );
            return totalProceeds;
        }
    }

    function internalSwap(
        uint _amount,
        address _fromToken,
        address _toToken,
        address recipient
    ) internal returns (uint) {
        (
            PathInfo memory path,
            uint tradeAmount,
            bool inverse
        ) = getProportionTradeAmount(_amount, _fromToken, _toToken);
        uint amountsOut = 0;
        if (tradeAmount > 0) {
            IERC20Upgradeable(_fromToken).safeIncreaseAllowance(
                path.bestRouter,
                tradeAmount
            );
            amountsOut = _swapTokenToToken(
                tradeAmount,
                inverse ? path.inversePath : path.path,
                path.bestRouter,
                recipient,
                path.slippage
            );
        }
        return amountsOut;
    }

    function getProportionTradeAmount(
        uint amountIn,
        address _fromToken,
        address _toToken
    )
        public
        view
        returns (PathInfo memory path, uint tradeAmount, bool inverse)
    {
        (path, inverse) = getTokenPath(_fromToken, _toToken);
        require(
            path.fromToken != address(0),
            "xWinSwap: path not defined for swap pair"
        );
        return (path, amountIn, inverse);
    }

    function getTokenPath(
        address _fromtoken,
        address _totoken
    ) public view returns (PathInfo memory _pathInfo, bool inverse) {
        PathInfo memory path = pathInfoRouter[_fromtoken][_totoken];
        return
            path.fromToken == address(0) && path.toToken == address(0)
                ? (pathInfoRouter[_totoken][_fromtoken], true)
                : (path, false);
    }

    function addTokenPath(
        address _router,
        address _fromtoken,
        address _totoken,
        address[] calldata path,
        uint256 _slippage
    ) external onlyExecutor {
        require(_fromtoken != _totoken, "from and to tokens are the same");
        require(
            path[0] == _fromtoken && path[path.length - 1] == _totoken,
            "Invalid path"
        );
        uint256[] memory amounts = IPancakeRouter02(_router).getAmountsOut(
            10 ** ERC20Upgradeable(_fromtoken).decimals(),
            path
        );
        require(amounts[amounts.length - 1] > 0, "router path check failed");

        PathInfo storage pathInfo_ = pathInfoRouter[_fromtoken][_totoken];
        address[] memory realPath = new address[](path.length);
        address[] memory _inversePath = new address[](path.length);
        for (uint256 i; i < path.length; i++) {
            realPath[i] = path[i];
            _inversePath[path.length - i - 1] = realPath[i];
        }
        pathInfo_.fromToken = _fromtoken;
        pathInfo_.toToken = _totoken;
        pathInfo_.path = realPath;
        pathInfo_.inversePath = _inversePath;
        pathInfo_.bestRouter = _router;
        pathInfo_.slippage = _slippage;
    }

    // check if input tokens are xWinStrategies, if yes handle the swap and return true else return false
    function _xWinStratSwap(
        uint256 _amount,
        address _fromToken,
        address _toToken
    ) internal returns (bool, uint) {
        if (isxWinStrategy(_fromToken)) {
            uint output = withdrawFromStrategy(_amount, _fromToken);
            address baseToken = getStrategyBaseToken(_fromToken);
            if (baseToken != _toToken) {
                uint newAmount = internalSwap(
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
                uint newAmount = internalSwap(
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
