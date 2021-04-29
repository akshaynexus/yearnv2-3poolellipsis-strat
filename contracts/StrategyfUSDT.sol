pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Strategy.sol";
import "../interfaces/IRewardToken.sol";

interface IERC20RewardToken is IRewardToken, IERC20 {}

contract StrategyfUSDT is Strategy {
    //ICE token address
    IERC20 public secondaryReward = IERC20(0xf16e81dce15B08F326220742020379B855B87DF9);

    IERC20 public iFUSDT = IERC20(0x049d68029688eAbF473097a2fC38ef61633A3C7A);

    IERC20 internal Stable3EPSToken = IERC20(0xaF4dE8E872131AE328Ce21D909C74705d3Aaf452);

    IERC20RewardToken fUSDTLP = IERC20RewardToken(0x373410A99B64B089DFE16F1088526D399252dacE);

    ICurveFi public fUSDTLPMinter = ICurveFi(0x556ea0b4c06D043806859c9490072FaadC104b63);
    IUniRouter internal sushiRouter = IUniRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    constructor(address _vault) public Strategy(_vault) {
        //3pool fusdt lp staker pid
        pid = 2;
        secondaryReward.safeApprove(address(sushiRouter), type(uint256).max);
        iFUSDT.safeApprove(address(fUSDTLPMinter), type(uint256).max);
        Stable3EPSToken.safeApprove(address(fUSDTLPMinter), type(uint256).max);
    }

    function name() external view override returns (string memory) {
        return "StrategyEllipsis3PoolFUSDT";
    }

    function pendingSecondaryReward() public view returns (uint256) {
        return fUSDTLP.earned(address(this), address(secondaryReward));
    }

    function updateSushiRouter(address _newRouter) external onlyGovernance {
        iEPS.safeApprove(address(sushiRouter), 0);
        sushiRouter = IUniRouter(_newRouter);
        iEPS.safeApprove(_newRouter, type(uint256).max);
    }

    function _getRewards(bytes memory swapData) internal virtual override {
        if (pendingReward() > 0) {
            uint256[] memory pids = new uint256[](1);
            pids[0] = pid;
            //First call claim EPS Rewards to minter
            farmer.claim(pids);
            //Now call exit and get EPS rewards
            rewardMinter.exit();
            //Next swap EPS for best stable to add via single side add
            _swapToBest(swapData);
            if (pendingSecondaryReward() > 0) {
                //Get ICE Reward
                fUSDTLP.getReward();
                //Swap ICE for best stable
                sushiRouter.swapExactTokensForTokens(
                    secondaryReward.balanceOf(address(this)),
                    uint256(0),
                    getTokenOutPath(address(secondaryReward), getBestStableToAdd()),
                    address(this),
                    now
                );
            }
            _addStablesLiq();
        }
    }

    function _addStablesLiq() internal virtual override {
        //Add liq to 3eps lp token first
        super._addStablesLiq();
        uint256[2] memory amounts = [iFUSDT.balanceOf(address(this)), Stable3EPSToken.balanceOf(address(this))];
        //Then add to fusdt LP with 3eps bal
        fUSDTLPMinter.add_liquidity(amounts, 0);
    }
}
