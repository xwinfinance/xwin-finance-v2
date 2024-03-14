// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Interface/IxWinPriceMaster.sol";

contract xWinDefi {
    struct UserInfo {
        uint256 amount;
        uint256 blockstart;
    }
    struct PoolInfo {
        address lpToken;
        uint256 rewardperblock;
        uint256 multiplier;
    }

    function DepositFarm(uint256 _pid, uint256 _amount) public {}

    function pendingXwin(
        uint256 _pid,
        address _user
    ) public view returns (uint256) {}

    function WithdrawFarm(uint256 _pid, uint256 _amount) public {}

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    PoolInfo[] public poolInfo;
}

contract xWinMasterChef is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken;
        uint256 endPeriod;
        uint256 allocPoint; // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardBlock; // Last block number that CAKEs distribution occurs.
        uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e18. See below.
        uint256 totalDeposit; // total lpToken deposited, since balanceOf() does not work for XWIN token being both LP and reward token
    }

    IxWinPriceMaster public xWinPriceMaster;
    IERC20Upgradeable public rewardsToken;
    address public usdtToken;
    address public burnAddress;
    xWinDefi public _xwinDefi;
    PoolInfo[] public poolInfo;
    uint256 public burnFee;
    // CAKE tokens created per block.
    uint256 public xwinPerBlock;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    uint256 public startBlock;
    uint256 public BONUS_MULTIPLIER;
    uint256 public xwinpid;
    uint256 public blocksPerDay;

    /// @notice mapping of a nft token to its current properties
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Received(address, uint);

    function initialize(
        string calldata name,
        string calldata symbol,
        address _usdtToken,
        uint256 _blocksPerDay
    ) external initializer {
        require(_usdtToken != address(0), "usdtToken input zero");
        __Ownable_init();
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();

        startBlock = block.number;
        blocksPerDay = _blocksPerDay;
        usdtToken = _usdtToken;
        totalAllocPoint = 0;
        BONUS_MULTIPLIER = 1;
        burnFee = 500;
        burnAddress = address(0x000000000000000000000000000000000000dEaD);
        _mint(address(this), 1 ether);
    }

    function farmTokenByAdmin() external onlyOwner {
        IERC20Upgradeable(address(this)).safeIncreaseAllowance(
            address(_xwinDefi),
            totalSupply()
        );
        _xwinDefi.DepositFarm(xwinpid, totalSupply());
    }

    function unFarmTokenByAdmin() external onlyOwner {
        _xwinDefi.WithdrawFarm(xwinpid, totalSupply());
    }

    // initial properties needed by admin
    function updateProperties(
        IERC20Upgradeable _rewardsToken,
        uint256 _xwinpid,
        uint256 _xwinPerBlock
    ) public onlyOwner {
        rewardsToken = _rewardsToken;
        xwinpid = _xwinpid;
        xwinPerBlock = _xwinPerBlock;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function updateSmartContract(
        address _xwinDefiaddr,
        address _xWinPriceMaster
    ) external onlyOwner {
        require(_xwinDefiaddr != address(0), "_xwinDefiaddr input is 0");
        require(_xWinPriceMaster != address(0), "_xWinPriceMaster input is 0");
        _xwinDefi = xWinDefi(_xwinDefiaddr);
        xWinPriceMaster = IxWinPriceMaster(_xWinPriceMaster);
    }

    // admin to stop the pool staking
    function stopPool(uint256 _pid) external onlyOwner {
        updatePool(_pid);
        _stopPool(_pid);
    }

    function _stopPool(uint256 _pid) internal {
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = 0;
        poolInfo[_pid].endPeriod = block.number;
        poolInfo[_pid].lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint - prevAllocPoint;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _lpToken,
        uint256 _duration
    ) external onlyOwner {
        massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accCakePerShare: 0,
                endPeriod: _duration * blocksPerDay + block.number,
                totalDeposit: 0
            })
        );
    }

    // Update the given pool's CAKE allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _newDuration
    ) external onlyOwner {
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].endPeriod = _newDuration * blocksPerDay + block.number;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        }
    }

    // View function to see pending CAKEs on frontend.
    function pendingRewards(
        uint256 _pid,
        address _user
    ) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 cakeReward = multiplier * xwinPerBlock * pool.allocPoint;
            accCakePerShare =
                accCakePerShare +
                ((cakeReward * 1e18) / totalAllocPoint / lpSupply);
        }
        uint256 pendingBeforeFee = ((user.amount * accCakePerShare) / 1e18) -
            user.rewardDebt;
        uint256 burnAmount = (pendingBeforeFee * burnFee) / 10000;
        return pendingBeforeFee - burnAmount;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint) {
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            poolInfo[_pid] = pool;
            return;
        }
        uint256 rewardBlock = pool.endPeriod > block.number
            ? block.number
            : pool.endPeriod;
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, rewardBlock);
        uint256 cakeReward = multiplier * xwinPerBlock * pool.allocPoint;

        //harvest from xwin farm
        _xwinDefi.DepositFarm(xwinpid, 0);
        pool.accCakePerShare =
            pool.accCakePerShare +
            ((cakeReward * 1e18) / totalAllocPoint / lpSupply);
        pool.lastRewardBlock = block.number;

        poolInfo[_pid] = pool;
        if (pool.endPeriod < block.number) {
            _stopPool(_pid);
        }
    }

    // Harvest All in one click
    function harvestAll() external nonReentrant {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            UserInfo memory user = userInfo[i][msg.sender];
            if (user.amount > 0) {
                _deposit(i, 0);
            }
        }
    }

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount
    ) external nonReentrant returns (uint256) {
        return _deposit(_pid, _amount);
    }

    function _deposit(
        uint256 _pid,
        uint256 _amount
    ) internal returns (uint256 rewardAmount) {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accCakePerShare) /
                1e18 -
                user.rewardDebt;
            if (pending > 0) {
                rewardAmount = safexWINTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            user.amount += _amount;
            pool.totalDeposit += _amount;
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
        }
        user.rewardDebt = (user.amount * pool.accCakePerShare) / 1e18;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(
        uint256 _pid,
        uint256 _amount
    ) external nonReentrant returns (uint256 rewardAmount) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accCakePerShare) / 1e18) -
            user.rewardDebt;
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.totalDeposit -= _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = (user.amount * pool.accCakePerShare) / 1e18;
        if (pending > 0) {
            rewardAmount = safexWINTransfer(msg.sender, pending);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Safe cake transfer function, just in case if rounding error causes pool to not have enough CAKEs.
    function safexWINTransfer(
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 burnFeeTotal = (_amount * burnFee) / 10000;
        rewardsToken.safeTransfer(burnAddress, burnFeeTotal);
        uint256 actualAmt = _amount - burnFeeTotal;
        rewardsToken.safeTransfer(_to, actualAmt);
        return actualAmt;
    }

    function harvest(uint256 _pid) external nonReentrant returns (uint256) {
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][msg.sender];
        uint256 pending = ((user.amount * pool.accCakePerShare) / 1e18) -
            user.rewardDebt;
        if (pending > 0) {
            safexWINTransfer(msg.sender, pending);
        }
        userInfo[_pid][msg.sender].rewardDebt =
            (user.amount * pool.accCakePerShare) /
            1e18;
        return pending;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalDeposit -= amount;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        // if (_pid == 0) {
        //     syrup.burn(msg.sender, amount);
        // }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function setBurnFee(uint256 _burnFee) external onlyOwner {
        require(_burnFee <= 2000, "burn fee cap at 20%");
        burnFee = _burnFee;
    }

    function setBonusMultiplier(uint256 _bonusMultiplier) external onlyOwner {
        BONUS_MULTIPLIER = _bonusMultiplier;
    }

    function setBlockPerDay(uint256 _blocksPerDay) external onlyOwner {
        blocksPerDay = _blocksPerDay;
    }

    function setUSDToken(address _newUSDToken) external onlyOwner {
        require(_newUSDToken != address(0), "_newUSDToken input is 0");
        usdtToken = _newUSDToken;
    }

    /// TODO : Get the APR for the pool
    function getAPR(uint _pid) external view returns (uint256 apr) {
        PoolInfo memory pool = poolInfo[_pid];
        uint lpBal = pool.totalDeposit;
        if (address(pool.lpToken) == address(0) || lpBal == 0) return 0;
        uint xwinPrice = IxWinPriceMaster(xWinPriceMaster).getPrice(
            address(rewardsToken),
            usdtToken
        );
        uint tokenPrice = IxWinPriceMaster(xWinPriceMaster).getPrice(
            address(pool.lpToken),
            usdtToken
        );
        uint xwinReward = xwinPerBlock * pool.allocPoint;
        uint accCakePerShare = (xwinReward * 1e18) / totalAllocPoint / lpBal;
        uint proceeds = accCakePerShare * blocksPerDay * 365 * xwinPrice;
        return (proceeds * 10000 * 100) / tokenPrice;
    }

    function getPoolUserRewardPerBlock(
        uint _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 userRatio = (user.amount * 1e18) / pool.totalDeposit;
        uint256 rewardPerBlockUser = (xwinPerBlock *
            pool.allocPoint *
            userRatio) / totalAllocPoint;
        rewardPerBlockUser = rewardPerBlockUser / 1e18;
        return rewardPerBlockUser;
    }
}
