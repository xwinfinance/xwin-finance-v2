// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "./Interface/AllPancakeInterface.sol";
import "./Interface/AggregatorV3Interface.sol";
import "./Interface/AccessControlledOffchainAggregatorInterface.sol";
import "./Interface/IxWinStrategy.sol";
import "./Interface/IxWinStrategyInteractor.sol";
import "./Interface/ITWAPOracle.sol";
import "./Library/Babylonian.sol";

contract xWinPriceMaster is OwnableUpgradeable {

    using SafeCastUpgradeable for int256;
    /*
    1: chainlink - usd - chainlink BTC/USDT rate from (BTC/USD & USDT/USD)
    2: chainLink direct - chainlink BTC/ETH rate
    3: xWinStrategy
    4: LP Token price
    5: TWAP
    */
    struct SourceMap {
        uint8 source;   //    1: chainlink - usd - chainlink 2: chainLink direct 3: xWinStrategy 0: TWAP
        address chainLinkAddr;  // only needed when it is 2: chainlink direct
    }
    
    modifier onlyExecutor {
        require(
            executors[msg.sender],
            "executor: wut?"
        );
        _;
    }

    IxWinStrategyInteractor stratInteractor;
    address _TWAPOracle;
    mapping(address => address) public chainLinkUSDpair;
    mapping (address => mapping (address => SourceMap)) public priceSourceMap;
    mapping(address => bool) public executors;
    
    function initialize(address _stratInteractor, address _twapAddress) initializer external {
        __Ownable_init();
        stratInteractor = IxWinStrategyInteractor(_stratInteractor);
        _TWAPOracle = _twapAddress;
        executors[msg.sender] = true;
    }
    
    function getPrice(address _from, address _to) public view returns (uint rate){

        bool flip = false;
        // if both from and to are same, the exrate is 1    
        uint256 decimalPlaces = 10 ** ERC20Upgradeable(_to).decimals();
        if(_from == _to) return decimalPlaces;
        
        SourceMap memory map = priceSourceMap[_from][_to];
        
        if(map.source == 0){
            map = priceSourceMap[_to][_from];
            address tempFrom = _from;
            _from = _to;
            _to = tempFrom;
            flip = true;
            decimalPlaces = 10 ** ERC20Upgradeable(_to).decimals();
            // no map source defined. revert
            require(map.source != 0, "PriceMaster: unsupported input addresses");
        }

        if(map.source == 1) {  // chainlink
            AggregatorV3Interface chainLinkFeedFrom = AggregatorV3Interface(chainLinkUSDpair[_from]);
            AggregatorV3Interface chainLinkFeedTo = AggregatorV3Interface(chainLinkUSDpair[_to]);

            uint256 chainlinkDecimalsFrom = 10 ** chainLinkFeedFrom.decimals();
            (/*uint80 roundID*/, int256 priceFrom, /*uint startedAt*/, /*uint256 updatedAt*/, /*uint80 answeredInRound*/) = chainLinkFeedFrom.latestRoundData();
            int192 min1 = AccessControlledOffchainAggregatorInterface(chainLinkFeedFrom.aggregator()).minAnswer();
            int192 max1 = AccessControlledOffchainAggregatorInterface(chainLinkFeedFrom.aggregator()).maxAnswer();
            uint256 chainlinkDecimalsTo = 10 ** chainLinkFeedTo.decimals();
            (/*uint80 roundID*/, int256 priceTo, /*uint startedAt*/, /*uint256 updatedAt*/, /*uint80 answeredInRound*/) = chainLinkFeedTo.latestRoundData();
            int192 min2 = AccessControlledOffchainAggregatorInterface(chainLinkFeedTo.aggregator()).minAnswer();
            int192 max2 = AccessControlledOffchainAggregatorInterface(chainLinkFeedTo.aggregator()).maxAnswer();
            require(priceFrom.toInt192() >= min1 && priceFrom.toInt192() <= max1 && priceTo.toInt192() >= min2 && priceTo.toInt192() <= max2, "Chainlink price outside operation range");
            uint256 rateTo = chainlinkDecimalsTo * chainlinkDecimalsTo;
            rate = priceFrom.toUint256() * rateTo * decimalPlaces / priceTo.toUint256() / chainlinkDecimalsFrom /chainlinkDecimalsTo;
        } else if (map.source == 2) {
            AggregatorV3Interface chainLinkFeed = AggregatorV3Interface(map.chainLinkAddr);
            uint256 chainlinkDecimals = 10 ** chainLinkFeed.decimals();
            (/*uint80 roundID*/, int256 price, /*uint startedAt*/, /*uint256 updatedAt*/, /*uint80 answeredInRound*/) = chainLinkFeed.latestRoundData();
            int192 min = AccessControlledOffchainAggregatorInterface(chainLinkFeed.aggregator()).minAnswer();
            int192 max = AccessControlledOffchainAggregatorInterface(chainLinkFeed.aggregator()).maxAnswer();
            require(price.toInt192() >= min && price.toInt192() <= max, "Chainlink price outside operation range");
            rate = price.toUint256() * decimalPlaces / chainlinkDecimals;
        } else if (map.source == 3) {
            rate = _convertFrom18(IxWinStrategy(_from).getUnitPrice(), _to); // This is 1e18
            address stratBase = stratInteractor.getStrategyBaseToken(_from);
            if (stratBase != _to) {
                uint tmpRate = getPrice(stratBase, _to);
                rate = rate * tmpRate / decimalPlaces;
            }
            
        } else if (map.source == 4) { // LP price
            rate = _getLPPrice(_from, _to);
        } else if (map.source == 5) { // twap price
            rate = _getTWAPPrice(_from, _to);
        }
        if(flip) rate = decimalPlaces * decimalPlaces / rate;
        require(rate > 0, "PriceMaster: returned 0 during call");
        return rate;
    }

    function _getTWAPPrice(address _from, address _to) internal view returns (uint amountOut) {
        uint decimals = 1 * (10 ** uint256(ERC20Upgradeable(_from).decimals()));
        amountOut = ITWAPOracle(_TWAPOracle).consult(_from, _to, decimals);
    }

    // method uses formula by: https://blog.alphaventuredao.io/fair-lp-token-pricing/
    function _getLPPrice(address _from, address _to) internal view returns (uint rate) {
    
        // uint256 decimalPlaces = 10 ** ERC20Upgradeable(_to).decimals();
        address underlying0 = IPancakePair(_from).token0();
        address underlying1 = IPancakePair(_from).token1();
        (uint reserves0, uint reserves1, ) = IPancakePair(_from).getReserves();

        uint totalSupply = IPancakePair(_from).totalSupply();
        uint256 rate0 = getPrice(underlying0, _to); // same decimal place as _to token
        uint256 rate1 = getPrice(underlying1, _to); // same decimal place as _to token

        uint256 reservesSqrt = Babylonian.sqrt(reserves0 * reserves1); // decimal place = (token0_decimal + token1_decimal) / 2
        uint256 rateSqrt = Babylonian.sqrt(rate0 * rate1);  // same decimal place as _to token

        // excess decimal
        uint8 d0 = ERC20Upgradeable(underlying0).decimals();
        uint8 d1 = ERC20Upgradeable(underlying1).decimals();
        uint8 d2 = IPancakePair(_from).decimals();
        uint8 d3 = (d0+d1)/2;
        return 2 * reservesSqrt * rateSqrt * 10**d2 / totalSupply / 10**d3;
    }

    function addPrice(
        address _from, 
        address _to,
        uint8 _source,
        address _chainLinkAddr
    ) external onlyExecutor {
        require(_source <= 5, "incorrect source");
        if (_source == 1) {
            require(chainLinkUSDpair[_from] != address(0) && chainLinkUSDpair[_to] != address(0), "token/usd pair missing");
        }
        if (_source == 2) {
            require(_chainLinkAddr != address(0), "_chainLinkAddr input empty");
        }
        SourceMap storage map = priceSourceMap[_from][_to];
        map.source = _source;
        map.chainLinkAddr = _chainLinkAddr;
    }

    function addChainlinkUSDPrice(address _token, address _chainLinkAddr) external onlyExecutor {
        require(_token != address(0) && _chainLinkAddr != address(0), "empty inputs");
        chainLinkUSDpair[_token] = _chainLinkAddr;
    }

    // Support multiple wallets or address as admin
    function setExecutor(address _address, bool _allow) external onlyOwner {
        executors[_address] = _allow;
    }

    function setTWAPOracle(address _address) external onlyOwner {
        require(_address != address(0), "_address input is 0");
        _TWAPOracle = _address;
    }

    function updateStratInteractor(address _stratInteractor) public onlyOwner {
        require(_stratInteractor != address(0), "_stratInteractor input is 0");
        stratInteractor = IxWinStrategyInteractor(_stratInteractor);
    }

    function _convertFrom18(uint value, address token) internal view returns (uint){
        if(value == 0) return 0;
        uint diffDecimal = 18 - ERC20Upgradeable(token).decimals();
        return diffDecimal > 0 ? (value / (10**diffDecimal)) : value; 
    } 

}