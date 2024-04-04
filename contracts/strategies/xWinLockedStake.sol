// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../Library/Babylonian.sol";
import "./xWinMasterChef.sol";

contract xWinLockedStake is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserInfo {
        uint256 shares; // number of shares for a user
        uint256 amount; // actual underlying amount
        uint256 lockedShares;
        uint256 rewardDebt;
        uint256 startTimestamp;
        uint256 endPeriodTimestamp;
        uint256 xWinFavor;
    }

    IERC20Upgradeable public token; // xwin token

    xWinMasterChef masterChef;

    mapping(address => UserInfo) public userInfo;

    uint256 public totalShares;
    uint256 public lastHarvestedTime;
    uint256 public totalLockedShares;
    uint256 public accXWINperLockedShare;
    address public treasury;
    uint256 public lockedRewardsVault;

    uint256 public performanceFee;
    uint256 public callFee;
    uint256 public blocksPerDay;
    uint256 public xwinpid;
    uint256 public lockpid;

    event Deposit(address indexed sender, uint256 amount, uint256 shares);
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event Harvest(
        address indexed sender,
        uint256 performanceFee,
        uint256 callFee
    );

    function initialize(
        IERC20Upgradeable _token,
        address _masterChef,
        address _treasury,
        uint256 _xwinpid,
        uint256 _lockpid
    ) external initializer {
        __Ownable_init();
        __ERC20_init("xWIN Locked Staking", "LS");
        __ReentrancyGuard_init();
        token = _token;
        treasury = _treasury;
        xwinpid = _xwinpid;
        lockpid = _lockpid;
        masterChef = xWinMasterChef(_masterChef);
        performanceFee = 200; // 2%
        callFee = 25; // 0.25%
        blocksPerDay = 28800;
    }

    function masterChefDeposit() external onlyOwner {
        // mint 1 token and put stake into locked masterChef pool
        _mint(address(this), 1 ether);
        IERC20Upgradeable(address(this)).safeIncreaseAllowance(
            address(masterChef),
            1 ether
        );
        masterChef.deposit(lockpid, 1 ether);
    }

    /// @notice Deposit into locked staking farm
    /// @notice If locked position already exists, this function acts to deposit more and extend locking period
    /// @param _amount Amount of xWin Tokens to deposit
    /// @param _duration Duration to lock
    function deposit(uint256 _amount, uint8 _duration) external nonReentrant {
        require(_amount > 0, "Nothing to deposit");
        require(_duration > 0 && _duration <= 52, "invalid duration");

        // auto XWIN logic
        _harvest();

        uint256 pool = totalXWINBalance();
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount * totalShares) / pool;
        } else {
            currentShares = _amount;
        }
        UserInfo memory user = userInfo[msg.sender];

        if (user.shares > 0) {
            // this deposit is a renew
            uint256 newEndTime = block.timestamp +
                convertWeeksToTimestamp(_duration);
            require(
                newEndTime > user.endPeriodTimestamp,
                "Invalid duration input"
            );

            uint256 oldLockedShares = user.lockedShares;
            uint256 rewardAmount = ((oldLockedShares * accXWINperLockedShare) /
                1e18) - user.rewardDebt;
            token.safeTransfer(msg.sender, rewardAmount);
            lockedRewardsVault -= rewardAmount;

            user.shares += currentShares;
            user.amount += _amount;
            user.endPeriodTimestamp = newEndTime;
            user.lockedShares = shareMultiplier(user.amount, _duration);
            user.rewardDebt =
                (user.lockedShares * accXWINperLockedShare) /
                1e18;
            user.xWinFavor = calculateFavor(
                user.amount,
                user.startTimestamp,
                user.endPeriodTimestamp
            );
            totalShares += currentShares;
            totalLockedShares =
                totalLockedShares -
                oldLockedShares +
                user.lockedShares;
        } else {
            //this is a new deposit
            user.shares = currentShares;
            user.amount = _amount;
            user.startTimestamp = block.timestamp;
            user.lockedShares = shareMultiplier(_amount, _duration);
            user.rewardDebt =
                (user.lockedShares * accXWINperLockedShare) /
                1e18;
            user.endPeriodTimestamp =
                block.timestamp +
                convertWeeksToTimestamp(_duration);
            user.xWinFavor = calculateFavor(
                user.amount,
                user.startTimestamp,
                user.endPeriodTimestamp
            );
            totalShares += currentShares;
            totalLockedShares += user.lockedShares;
        }

        userInfo[msg.sender] = user;
        _earn();
        emit Deposit(msg.sender, _amount, currentShares);
    }

    /// To re-invest rewards for compounding rewards
    function harvest() public nonReentrant {
        _harvest();
    }

    function _harvest() internal {
        masterChef.deposit(xwinpid, 0);
        uint256 bal = available();
        uint256 currentPerformanceFee = (bal * performanceFee) / 10000;
        token.safeTransfer(treasury, currentPerformanceFee);

        uint256 currentCallFee = (bal * callFee) / 10000;
        token.safeTransfer(msg.sender, currentCallFee);
        harvestLockBonus();
        _earn();

        lastHarvestedTime = block.timestamp;
    }

    /**
     * @notice Collect locking bonus
     */
    function harvestLockBonus() internal {
        if (totalLockedShares == 0) return;
        uint256 harvestAmount = masterChef.deposit(lockpid, 0);
        lockedRewardsVault += harvestAmount;
        accXWINperLockedShare += (1e18 * harvestAmount) / totalLockedShares;
    }

    /**
     * @notice Withdraws everything from user
     */
    function withdraw() external nonReentrant {
        UserInfo memory user = userInfo[msg.sender];
        require(user.shares > 0, "Nothing to withdraw");
        require(
            user.endPeriodTimestamp <= block.timestamp,
            "tokens still locked"
        );
        _harvest();
        delete userInfo[msg.sender];

        uint256 withdrawAmount = _doWithdraw(user);

        totalLockedShares -= user.lockedShares;
        totalShares -= user.shares;
        emit Withdraw(msg.sender, withdrawAmount, user.shares);
    }

    /**
     * @notice Reinvest reward tokens into MasterChef to compound staking rewards
     */
    function _earn() internal {
        uint256 bal = available();
        if (bal > 0) {
            IERC20Upgradeable(token).safeIncreaseAllowance(
                address(masterChef),
                bal
            );
            masterChef.deposit(xwinpid, bal);
        }
    }

    /**
     * @notice Sets treasury address
     * @dev Only callable by the contract owner.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
    }

    /**
     * @notice Sets call fee and performance fee
     * @dev Only callable by the contract admin.
     */
    function setFees(
        uint256 _callFee,
        uint256 _performanceFee
    ) external onlyOwner {
        require(_callFee <= 100, "call fee cap at 1%");
        require(_performanceFee <= 300, "perform fee cap at 3%");
        callFee = _callFee;
        performanceFee = _performanceFee;
    }

    function setBlocksPerDay(uint256 _blocksPerDay) external onlyOwner {
        blocksPerDay = _blocksPerDay;
    }

    function migrateMasterChef(
        address _newMasterChef,
        uint256 _xwinpid,
        uint256 _lockpid
    ) external onlyOwner {
        _harvest();
        (uint totalAmt, ) = masterChef.userInfo(xwinpid, address(this));
        masterChef.withdraw(xwinpid, totalAmt);
        masterChef.withdraw(lockpid, 1 ether);

        masterChef = xWinMasterChef(_newMasterChef);
        IERC20Upgradeable(token).safeIncreaseAllowance(
            _newMasterChef,
            totalAmt
        );
        IERC20Upgradeable(address(this)).safeIncreaseAllowance(
            _newMasterChef,
            1 ether
        );
        xwinpid = _xwinpid;
        lockpid = _lockpid;

        masterChef.deposit(xwinpid, totalAmt);
        masterChef.deposit(lockpid, 1 ether);
    }

    /**
     * @notice Calculates the expected harvest reward from third party
     * @return Expected reward to collect in CAKE
     */
    function calculateHarvestCakeRewards() external view returns (uint256) {
        uint256 amount = masterChef.pendingRewards(xwinpid, address(this));
        amount = amount + available();
        uint256 currentCallFee = (amount * callFee) / 10000;
        return currentCallFee;
    }

    /**
     * @notice Calculates the total pending rewards that can be restaked
     * @return Returns total pending cake rewards
     */
    function calculateTotalPendingCakeRewards()
        external
        view
        returns (uint256)
    {
        uint256 amount = masterChef.pendingRewards(xwinpid, address(this));

        amount = amount + available();

        return amount;
    }

    /**
     * @notice Calculate user withdraw rewards
     * @return Returns total pending cake rewards
     */
    function _doWithdraw(UserInfo memory user) internal returns (uint256) {
        // auto XWIN portion
        uint256 currentAmount = (totalXWINBalance() * user.shares) /
            totalShares;

        // bonus portion
        uint256 bonusAmount = ((user.lockedShares * accXWINperLockedShare) /
            1e18) - user.rewardDebt;
        uint256 amount = currentAmount + bonusAmount;

        uint256 currentBalance = available();
        if (currentBalance < currentAmount) {
            uint256 diff = currentAmount - currentBalance;
            masterChef.withdraw(xwinpid, diff);
        }
        lockedRewardsVault -= bonusAmount;
        token.safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return
            totalShares == 0 ? 1e18 : (totalXWINBalance() * 1e18) / totalShares;
    }

    /**
     * @notice Custom logic for how much the vault allows to be borrowed
     * @dev The contract puts all of the tokens except for lockedRewards to work.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this)) - lockedRewardsVault;
    }

    function getFavor(address _user) external view returns (uint256) {
        return userInfo[_user].xWinFavor;
    }

    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in MasterChef
     */
    function totalXWINBalance() public view returns (uint256) {
        (uint depositAmount, ) = masterChef.userInfo(xwinpid, address(this));
        uint pending = masterChef.pendingRewards(xwinpid, address(this));
        return
            token.balanceOf(address(this)) +
            depositAmount +
            pending -
            lockedRewardsVault;
    }

    function shareMultiplier(
        uint256 amount,
        uint8 period
    ) public pure returns (uint256) {
        return (amount * (period + 50)) / 51;
    }

    function getUserPosition(
        address _user
    ) public view returns (uint256 rewardAmount, uint256 xwinAmount) {
        UserInfo memory user = userInfo[_user];
        if (totalShares == 0 || user.shares == 0) return (0, 0);
        xwinAmount = (totalXWINBalance() * user.shares) / totalShares;
        uint pendingFromBonusPool = masterChef.pendingRewards(
            lockpid,
            address(this)
        );
        uint256 tempaccXWINperLockedShare = accXWINperLockedShare +
            (1e18 * pendingFromBonusPool) /
            totalLockedShares;
        rewardAmount =
            ((user.lockedShares * tempaccXWINperLockedShare) / 1e18) -
            user.rewardDebt;
        return (rewardAmount, xwinAmount);
    }

    function convertWeeksToTimestamp(
        uint256 w
    ) internal pure returns (uint256) {
        return w * 1 weeks;
    }

    function calculateFavor(
        uint256 amount,
        uint256 startTimestamp,
        uint256 endTimeStamp
    ) private pure returns (uint256 favor) {
        uint256 diff = 1 + (endTimeStamp - startTimestamp) / 86400;
        if (diff > 365) {
            diff = 365;
        }
        uint256 tmp = (amount * diff * diff) / 1e18;
        tmp = ((Babylonian.sqrt(tmp) * 1e18) * 5000) / 81600;
        favor = tmp / 1e18;
        if (favor > 5000) {
            favor = 5000;
        }
    }

    function getUserCompoundAPYrate(
        address _user
    ) external view returns (uint256 estimatedDailyRate) {
        UserInfo memory user = userInfo[_user];
        if (user.amount == 0) return 0;
        uint emmission = masterChef.getPoolUserRewardPerBlock(
            xwinpid,
            address(this)
        );
        uint256 estimatedDailyReward = emmission * blocksPerDay * user.shares;
        estimatedDailyRate =
            (estimatedDailyReward * 1e18) /
            totalShares /
            user.amount;
        // calculate in frontend (1 + (estimatedDailyRate / 1e18)) ** 365 - 1
    }

    function getUserLockingBonusAPR(
        address _user
    ) external view returns (uint256 apr) {
        if (totalLockedShares == 0) return 0;
        UserInfo memory user = userInfo[_user];
        if (user.amount == 0) return 0;
        uint256 emmission = masterChef.getPoolUserRewardPerBlock(
            lockpid,
            address(this)
        );
        uint256 estimatedReward = emmission *
            365 *
            blocksPerDay *
            user.lockedShares;
        apr = (estimatedReward * 10000) / totalLockedShares / user.amount;
    }

    function getEstimatedDepositAPY(
        uint256 _amount,
        uint8 _duration
    )
        external
        view
        returns (uint256 estimatedDailyRate, uint256 estimatedBonusApr)
    {
        uint emmissionCompound = masterChef.getPoolUserRewardPerBlock(
            xwinpid,
            address(this)
        );
        uint256 emmissionBonus = masterChef.getPoolUserRewardPerBlock(
            lockpid,
            address(this)
        );

        if (_amount == 0) return (0, 0);
        // Compound rate calculation
        uint256 newShares = 0;
        if (totalShares != 0) {
            newShares = (_amount * totalShares) / totalXWINBalance();
        } else {
            newShares = _amount;
        }
        uint256 estimatedDailyReward = emmissionCompound *
            blocksPerDay *
            newShares;
        // this is returned
        estimatedDailyRate =
            (estimatedDailyReward * 1e18) /
            (totalShares + newShares) /
            _amount;
        // calculate in frontend (1 + (estimatedDailyRate / 1e18)) ** 365 - 1

        // Bonus Apr calculation
        uint256 newLockedShares = shareMultiplier(_amount, _duration);
        uint256 estimatedReward = emmissionBonus *
            365 *
            blocksPerDay *
            newLockedShares;
        // this is returned
        estimatedBonusApr =
            (estimatedReward * 10000) /
            (totalLockedShares + newLockedShares) /
            _amount;
    }
}
