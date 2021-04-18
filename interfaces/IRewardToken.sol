pragma solidity 0.6.12;

interface IRewardToken {
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external;

    function burnFrom(address _to, uint256 _value) external returns (bool);

    function depositedBalanceOf(address) external view returns (uint256);

    function earned(address account, address _rewardsToken) external view returns (uint256);

    function getReward() external;

    function getRewardForDuration(address _rewardsToken) external view returns (uint256);

    function lastTimeRewardApplicable(address _rewardsToken) external view returns (uint256);

    function lpStaker() external view returns (address);

    function rewardTokens(uint256) external view returns (address);

    function rewards(address, address) external view returns (uint256);

    function userRewardPerTokenPaid(address, address) external view returns (uint256);
}
