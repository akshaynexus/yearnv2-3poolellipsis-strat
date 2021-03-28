pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface ILiqRewards {
    // Info of each user.

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 oracleIndex; // Index value for oracles array indicating which price multiplier to use.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardTime; // Last second that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
    }

    function claim(uint256[] memory _pids) external;

    function claimableReward(uint256 _pid, address _user) external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256) external view returns (PoolInfo memory);

    function userInfo(uint256, address) external view returns (UserInfo memory);

    function withdraw(uint256 _pid, uint256 _amount) external;
}
