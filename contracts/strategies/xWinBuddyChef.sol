// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinBuddyChef is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken;
        IERC20Upgradeable rewardToken;
        uint endPeriod;
        uint lastRewardBlock; // Last block number that CAKEs distribution occurs.
        uint accCakePerShare; // Accumulated CAKEs per share, times 1e18. See below.
        uint tokenPerBlock;
        uint totalStaked;
        uint totalBuddyTokens;
    }

    IxWinPriceMaster xWinPriceMaster;
    address public usdtToken;
    address public devAddress;
    PoolInfo[] public poolInfo;
    uint public devFee;
    uint public startBlock;
    uint public BONUS_MULTIPLIER;
    uint public blocksPerDay;

    /// @notice mapping of a nft token to its current properties
    mapping(uint => mapping(address => UserInfo)) public userInfo;

    event Deposit(address user, uint256 pid, uint256 amount);
    event Withdraw(address user, uint256 pid, uint256 amount);
    event EmergencyWithdraw(address user, uint256 pid, uint256 amount);
    event Received(address, uint);

    function initialize(
        address _devAddress,
        address _xWinPriceMaster,
        address _usdtToken,
        uint _blocksPerDay
    ) public initializer {
        require(_devAddress != address(0), "devAddress input zero");
        require(
            _xWinPriceMaster != address(0),
            "xWinPriceMaster addr input zero"
        );
        require(_usdtToken != address(0), "usdtToken input zero");
        __Ownable_init();
        __ReentrancyGuard_init();
        devAddress = _devAddress;
        startBlock = block.number;
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
        usdtToken = _usdtToken;
        blocksPerDay = _blocksPerDay;
        devFee = 500;
        BONUS_MULTIPLIER = 1;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // admin to stop the pool staking
    function stopPool(uint _pid) public onlyOwner {
        _stopPool(_pid);
    }

    // admin to stop the pool staking
    function updateDevAddress(address _devAdd) public onlyOwner {
        require(_devAdd != address(0), "_devAdd input is 0");
        devAddress = _devAdd;
    }

    function _stopPool(uint _pid) internal {
        poolInfo[_pid].endPeriod = block.number;
        poolInfo[_pid].lastRewardBlock = block.number;
        poolInfo[_pid].tokenPerBlock = 0;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        IERC20Upgradeable _lpToken,
        IERC20Upgradeable _rewardToken,
        uint _duration,
        uint _totalBuddyTokens
    ) public onlyOwner {
        require(_lpToken != _rewardToken, "cannot be same token");
        _rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            _totalBuddyTokens
        );
        massUpdatePools();
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                rewardToken: _rewardToken,
                lastRewardBlock: block.number > startBlock
                    ? block.number
                    : startBlock,
                accCakePerShare: 0,
                endPeriod: _duration * blocksPerDay + block.number,
                tokenPerBlock: _totalBuddyTokens / _duration / blocksPerDay,
                totalBuddyTokens: _totalBuddyTokens,
                totalStaked: 0
            })
        );
    }

    // Update the given pool's token allocation in case of duration extended and new total buddy tokens amount.
    function set(
        uint _pid,
        uint _newDuration,
        uint _totalBuddyTokens,
        uint _amountToAdd
    ) public onlyOwner {
        massUpdatePools();
        PoolInfo memory pool = poolInfo[_pid];
        pool.rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            _amountToAdd
        );
        if (pool.endPeriod > block.number) {
            uint tokensLeftover = (pool.endPeriod - block.number) *
                pool.tokenPerBlock;
            require(
                _amountToAdd + tokensLeftover >= _totalBuddyTokens,
                "insufficient amt to add"
            );
        } else {
            require(
                _amountToAdd >= _totalBuddyTokens,
                "insufficient amt to add"
            );
        }
        pool.endPeriod = _newDuration * blocksPerDay + block.number;
        pool.tokenPerBlock = _totalBuddyTokens / _newDuration / blocksPerDay;
        pool.totalBuddyTokens = _totalBuddyTokens;

        poolInfo[_pid] = pool;
    }

    // View function to see pending CAKEs on frontend.
    function pendingRewards(
        uint256 _pid,
        address _user
    ) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accCakePerShare = pool.accCakePerShare;
        if (block.number > pool.lastRewardBlock && pool.totalStaked != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number,
                pool.endPeriod
            );
            uint256 cakeReward = multiplier * pool.tokenPerBlock;
            accCakePerShare =
                accCakePerShare +
                (cakeReward * 1e18) /
                pool.totalStaked;
        }
        uint rewardBal = ((user.amount * accCakePerShare) / 1e18) -
            user.rewardDebt;
        return rewardBal;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint _from,
        uint _to,
        uint _endBlock
    ) public view returns (uint) {
        _to = _to > _endBlock ? _endBlock : _to;
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.totalStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint multiplier = getMultiplier(
            pool.lastRewardBlock,
            block.number,
            pool.endPeriod
        );
        uint cakeReward = multiplier * pool.tokenPerBlock;
        pool.accCakePerShare =
            pool.accCakePerShare +
            ((cakeReward * 1e18) / pool.totalStaked);
        pool.lastRewardBlock = block.number;

        if (pool.endPeriod < block.number) {
            _stopPool(_pid);
        }
    }

    // Harvest All in one click
    function harvestAll() public nonReentrant {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            UserInfo memory user = userInfo[i][msg.sender];
            if (user.amount > 0) {
                _deposit(i, 0);
            }
        }
    }

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        _deposit(_pid, _amount);
    }

    function _deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accCakePerShare) /
                1e18 -
                user.rewardDebt;
            if (pending > 0) {
                safeTokenTransfer(pool.rewardToken, msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            pool.totalStaked = pool.totalStaked + _amount;
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = (user.amount * pool.accCakePerShare) / 1e18;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accCakePerShare) / 1e18) -
            user.rewardDebt;
        if (pending > 0) {
            safeTokenTransfer(pool.rewardToken, msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.totalStaked = pool.totalStaked - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = (user.amount * pool.accCakePerShare) / 1e18;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Safe cake safeTransfer function, just in case if rounding error causes pool to not have enough CAKEs.
    function safeTokenTransfer(
        IERC20Upgradeable rewardToken,
        address _to,
        uint256 _amount
    ) internal {
        uint bal = rewardToken.balanceOf(address(this));
        _amount = bal < _amount ? bal : _amount;
        uint devFeeTotal = (_amount * devFee) / 10000;
        rewardToken.safeTransfer(devAddress, devFeeTotal);
        rewardToken.safeTransfer(_to, _amount - devFeeTotal);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function setPriceMaster(address _newPriceMaster) external onlyOwner {
        require(_newPriceMaster != address(0), "_newPriceMaster input is 0");
        xWinPriceMaster = IxWinPriceMaster(_newPriceMaster);
    }

    function setUSDToken(address _newUSDAddr) external onlyOwner {
        require(_newUSDAddr != address(0), "_newUSDAddr input is 0");
        usdtToken = _newUSDAddr;
    }

    function setDevFee(uint256 _newDevFee) external onlyOwner {
        require(_newDevFee <= 1000, "dev Fee capped at 10%");
        devFee = _newDevFee;
    }

    function setBonusMultiplier(uint256 _newMultiplier) external onlyOwner {
        BONUS_MULTIPLIER = _newMultiplier;
    }

    function setBlocksPerDay(uint256 _newBlocksPerDay) external onlyOwner {
        blocksPerDay = _newBlocksPerDay;
    }
}
