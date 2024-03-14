// // SPDX-License-Identifier: GPL-3.0-or-later

// pragma solidity ^0.8.9;


// interface IVenusStaking {

//     /**
//      * @notice Deposit XVSVault for XVS allocation
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _amount The amount to deposit to vault
//      */
//     function deposit(address _rewardToken, uint256 _pid, uint256 _amount) external;

//     /**
//      * @notice Claim rewards for pool
//      * @param _account The account for which to claim rewards
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      */
//     function claim(address _account, address _rewardToken, uint256 _pid) external;

//     /**
//      * @notice Execute withdrawal to XVSVault for XVS allocation
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      */
//     function executeWithdrawal(address _rewardToken, uint256 _pid) external;

//     /**
//      * @notice Request withdrawal to XVSVault for XVS allocation
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _amount The amount to withdraw from the vault
//      */
//     function requestWithdrawal(address _rewardToken, uint256 _pid, uint256 _amount) external;

//     /**
//      * @notice Get unlocked withdrawal amount
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _user The User Address
//      * @return withdrawalAmount Amount that the user can withdraw
//      */
//     function getEligibleWithdrawalAmount(
//         address _rewardToken,
//         uint256 _pid,
//         address _user
//     ) external view returns (uint withdrawalAmount);
//     /**
//      * @notice Get requested amount
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _user The User Address
//      * @return Total amount of requested but not yet executed withdrawals (including both executable and locked ones)
//      */
//     function getRequestedAmount(address _rewardToken, uint256 _pid, address _user) external view returns (uint256);
//     /**
//      * @notice Returns the array of withdrawal requests that have not been executed yet
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _user The User Address
//      * @return An array of withdrawal requests
//      */
//     function getWithdrawalRequests(
//         address _rewardToken,
//         uint256 _pid,
//         address _user
//     ) external view returns (WithdrawalRequest[] memory);

//     /**
//      * @notice View function to see pending XVSs on frontend
//      * @param _rewardToken Reward token address
//      * @param _pid Pool index
//      * @param _user User address
//      * @return Reward the user is eligible for in this pool, in terms of _rewardToken
//      */
//     function pendingReward(address _rewardToken, uint256 _pid, address _user) external view returns (uint256);

//     /**
//      * @notice Get user info with reward token address and pid
//      * @param _rewardToken Reward token address
//      * @param _pid Pool index
//      * @param _user User address
//      * @return amount Deposited amount
//      * @return rewardDebt Reward debt (technical value used to track past payouts)
//      * @return pendingWithdrawals Requested but not yet executed withdrawals
//      */
//     function getUserInfo(
//         address _rewardToken,
//         uint256 _pid,
//         address _user
//     ) external view returns (uint256 amount, uint256 rewardDebt, uint256 pendingWithdrawals);
//     /**
//      * @notice Gets the total pending withdrawal amount of a user before upgrade
//      * @param _rewardToken The Reward Token Address
//      * @param _pid The Pool Index
//      * @param _user The address of the user
//      * @return beforeUpgradeWithdrawalAmount Total pending withdrawal amount in requests made before the vault upgrade
//      */
//     function pendingWithdrawalsBeforeUpgrade(
//         address _rewardToken,
//         uint256 _pid,
//         address _user
//     ) public view returns (uint256 beforeUpgradeWithdrawalAmount);
//     /**
//      * @notice Get the XVS stake balance of an account (excluding the pending withdrawals)
//      * @param account The address of the account to check
//      * @return The balance that user staked
//      */
//     function getStakeAmount(address account) internal view returns (uint96);

//     /**
//      * @notice Delegate votes from `msg.sender` to `delegatee`
//      * @param delegatee The address to delegate votes to
//      */
//     function delegate(address delegatee) external;


//     /**
//      * @notice Gets the current votes balance for `account`
//      * @param account The address to get votes balance
//      * @return The number of current votes for `account`
//      */
//     function getCurrentVotes(address account) external view;


//     /**
//      * @notice Determine the xvs stake balance for an account
//      * @param account The address of the account to check
//      * @param blockNumber The block number to get the vote balance at
//      * @return The balance that user staked
//      */
//     function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);

// }