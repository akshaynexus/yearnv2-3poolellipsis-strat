// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import "../interfaces/ICurveFi.sol";
import "../interfaces/ILiqRewards.sol";

interface IRewardMinter {
    //This gives us the 50% EPS rewards and BUSD
    function exit() external;
}

interface IUniRouter {
    function swapExactTokensForTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public pid = 1;

    address[] internal path;
    address internal wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    IERC20 internal iBUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IERC20 internal iEPS = IERC20(0xA7f552078dcC247C2684336020c03648500C6d9F);

    IUniRouter public pancakeRouter = IUniRouter(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    ICurveFi public Stable3EPS = ICurveFi(0x160CAed03795365F3A589f10C379FfA7d75d4E76);
    ILiqRewards public farmer = ILiqRewards(0xcce949De564fE60e7f96C85e55177F8B9E4CF61b);
    IRewardMinter public rewardMinter = IRewardMinter(0x4076CC26EFeE47825917D0feC3A79d0bB9a6bB5c);

    constructor(address _vault) public BaseStrategy(_vault) {
        want.safeApprove(address(farmer), type(uint256).max);
        iBUSD.safeApprove(address(Stable3EPS), type(uint256).max);
        iEPS.safeApprove(address(pancakeRouter), type(uint256).max);
        path = getTokenOutPath(address(iEPS), address(iBUSD));
    }

    function name() external view override returns (string memory) {
        return "StrategyEllipsis3Pool";
    }

    // returns balance of 3EPS
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    //Returns staked value
    function balanceOfStake() public view returns (uint256) {
        return farmer.userInfo(pid, address(this)).amount;
    }

    function pendingReward() public view returns (uint256) {
        return farmer.claimableReward(pid, address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfStake());
    }

    function getSwapPath() external view returns (address[] memory) {
        return path;
    }

    function _deposit(uint256 amount) internal {
        farmer.deposit(pid, amount);
    }

    function _withdraw(uint256 amount) internal {
        farmer.withdraw(pid, amount);
    }

    function _getRewards() internal {
        if (pendingReward() > 0) {
            uint256[] memory pids = new uint256[](1);
            pids[0] = pid;
            //First call deposit with amount as 0 to mint rewards to minter
            farmer.claim(pids);
            //Now call exit and get EPS rewards
            rewardMinter.exit();
            //Next swap EPS for BUSD
            _swapToBUSD();
            //Add busd liq from all the remaining busd
            _addBUSDLiq();
        }
    }

    function getTokenOutPath(address _token_in, address _token_out) internal view returns (address[] memory _path) {
        bool is_wbnb = _token_in == address(wbnb) || _token_out == address(wbnb);
        _path = new address[](is_wbnb ? 2 : 3);
        _path[0] = _token_in;
        if (is_wbnb) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(wbnb);
            _path[2] = _token_out;
        }
    }

    //sell all function
    function _swapToBUSD() internal {
        uint256 rewardBal = iEPS.balanceOf(address(this));
        if (rewardBal == 0) {
            return;
        }
        if (path.length == 0) {
            pancakeRouter.swapExactTokensForTokens(rewardBal, uint256(0), getTokenOutPath(address(iEPS), address(iBUSD)), address(this), now);
        } else {
            pancakeRouter.swapExactTokensForTokens(rewardBal, uint256(0), path, address(this), now);
        }
    }

    function _addBUSDLiq() internal {
        uint256[3] memory amounts = [iBUSD.balanceOf(address(this)), 0, 0];
        Stable3EPS.add_liquidity(amounts, 0);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        uint256 balanceOfWantBefore = balanceOfWant();
        if (!emergencyExit) _getRewards();

        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _wantAvailable = balanceOfWant();

        if (_debtOutstanding >= _wantAvailable) {
            return;
        }

        uint256 toInvest = _wantAvailable.sub(_debtOutstanding);

        if (toInvest > 0) {
            _deposit(toInvest);
        }
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 balanceWant = balanceOfWant();
        uint256 balanceStaked = balanceOfStake();
        if (_amountNeeded > balanceWant) {
            // unstake needed amount
            _withdraw((Math.min(balanceStaked, _amountNeeded - balanceWant)));
        }
        // Since we might free more than needed, let's send back the min
        _liquidatedAmount = Math.min(balanceOfWant(), _amountNeeded);
    }

    function prepareMigration(address _newStrategy) internal override {
        // If we have pending rewards,take that out
        if (emergencyExit) {
            //Do emergency withdraw flow
            farmer.emergencyWithdraw(pid);
        } else {
            _getRewards();
            _withdraw(balanceOfStake());
        }
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    function protectedTokens() internal view override returns (address[] memory) {}
}
