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

    address internal wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    //Used to swap for best price with 1inch swaps
    address public OneInchRouter = 0x11111112542D85B3EF69AE05771c2dCCff4fAa26;

    IERC20 internal iBUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IERC20 internal iUSDC = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
    IERC20 internal iUSDT = IERC20(0x55d398326f99059fF775485246999027B3197955);

    IERC20 internal iEPS = IERC20(0xA7f552078dcC247C2684336020c03648500C6d9F);

    IUniRouter public pancakeRouter = IUniRouter(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    ICurveFi public Stable3EPS = ICurveFi(0x160CAed03795365F3A589f10C379FfA7d75d4E76);
    ILiqRewards public farmer = ILiqRewards(0xcce949De564fE60e7f96C85e55177F8B9E4CF61b);
    IRewardMinter public rewardMinter = IRewardMinter(0x4076CC26EFeE47825917D0feC3A79d0bB9a6bB5c);

    constructor(address _vault) public BaseStrategy(_vault) {
        want.safeApprove(address(farmer), type(uint256).max);
        iBUSD.safeApprove(address(Stable3EPS), type(uint256).max);
        iUSDC.safeApprove(address(Stable3EPS), type(uint256).max);
        iUSDT.safeApprove(address(Stable3EPS), type(uint256).max);
        iEPS.safeApprove(address(pancakeRouter), type(uint256).max);
        iEPS.safeApprove(OneInchRouter, type(uint256).max);
    }

    function name() external view virtual override returns (string memory) {
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
        //Half the reward is returned as pending reward since we exit early
        return farmer.claimableReward(pid, address(this)).mul(50).div(100);
    }

    function getRewardAmountToSell() external view returns (uint256) {
        return pendingReward() + iEPS.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfStake());
    }

    function updateOneInchRouter(address _newRouter) external onlyGovernance {
        //Revoke approve for old router
        iEPS.safeApprove(OneInchRouter, 0);
        OneInchRouter = _newRouter;
        //Approve for new router
        iEPS.safeApprove(_newRouter, type(uint256).max);
    }

    function updatePancakeRouter(address _newRouter) external onlyGovernance {
        iEPS.safeApprove(address(pancakeRouter), 0);
        pancakeRouter = IUniRouter(_newRouter);
        iEPS.safeApprove(_newRouter, type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        farmer.deposit(pid, amount);
    }

    function _withdraw(uint256 amount) internal {
        farmer.withdraw(pid, amount);
    }

    function _getRewards(bytes memory _swapData) internal virtual {
        if (pendingReward() > 0) {
            uint256[] memory pids = new uint256[](1);
            pids[0] = pid;
            //First call claim EPS Rewards to minter
            farmer.claim(pids);
            //Now call exit and get EPS rewards
            rewardMinter.exit();
            //Next swap EPS for best stablecoin
            _swapToBest(_swapData);
            //Add liq for lp tokens
            _addStablesLiq();
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
    function _swapToBest(bytes memory _swapOneInch) internal {
        uint256 rewardBal = iEPS.balanceOf(address(this));
        if (rewardBal == 0) {
            return;
        }
        //Default to pcs swap if input data is null
        if (_swapOneInch.length == 0)
            pancakeRouter.swapExactTokensForTokens(
                rewardBal,
                uint256(0),
                getTokenOutPath(address(iEPS), getBestStableToAdd()),
                address(this),
                now
            );
            //Else swap via 1inch
        else {
            (bool success, ) = OneInchRouter.call{value: 0}(_swapOneInch);
            require(success, "OneInch Swap fails");
        }
    }

    function _addStablesLiq() internal virtual {
        uint256[3] memory amounts = [iBUSD.balanceOf(address(this)), iUSDC.balanceOf(address(this)), iUSDT.balanceOf(address(this))];
        Stable3EPS.add_liquidity(amounts, 0);
    }

    function getBestStableToAdd() public view returns (address) {
        //Get all balances of 3eps contract
        uint256 busdBal = iBUSD.balanceOf(address(Stable3EPS));
        uint256 usdcBal = iUSDC.balanceOf(address(Stable3EPS));
        uint256 usdtBal = iUSDT.balanceOf(address(Stable3EPS));
        //return which one has the least in lp pool
        if (usdtBal < usdcBal && usdtBal < busdBal) return address(iUSDT);
        else if (usdcBal < usdtBal && usdcBal < busdBal) return address(iUSDC);
        else return address(iBUSD);
    }

    //Harvest code copied with added param to pass call data to execute 1inch swap
    function harvest(bytes calldata swapData) external onlyKeepers {
        uint256 profit = 0;
        uint256 loss = 0;
        uint256 debtOutstanding = vault.debtOutstanding();
        uint256 debtPayment = 0;
        if (emergencyExit) {
            // Free up as much capital as possible
            uint256 totalAssets = estimatedTotalAssets();
            // NOTE: use the larger of total assets or debt outstanding to book losses properly
            (debtPayment, loss) = liquidatePosition(totalAssets > debtOutstanding ? totalAssets : debtOutstanding);
            // NOTE: take up any remainder here as profit
            if (debtPayment > debtOutstanding) {
                profit = debtPayment.sub(debtOutstanding);
                debtPayment = debtOutstanding;
            }
        } else {
            // Free up returns for Vault to pull
            (profit, loss, debtPayment) = prepareReturnWithOneInch(debtOutstanding, swapData);
        }

        // Allow Vault to take up to the "harvested" balance of this contract,
        // which is the amount it has earned since the last time it reported to
        // the Vault.
        debtOutstanding = vault.report(profit, loss, debtPayment);

        // Check if free returns are left, and re-invest them
        adjustPosition(debtOutstanding);

        emit Harvested(profit, loss, debtPayment, debtOutstanding);
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
        if (!emergencyExit) _getRewards(new bytes(0));

        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function prepareReturnWithOneInch(uint256 _debtOutstanding, bytes memory _swapData)
        internal
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
        if (!emergencyExit) _getRewards(_swapData);

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
            _getRewards(new bytes(0));
            _withdraw(balanceOfStake());
        }
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    function protectedTokens() internal view override returns (address[] memory) {}
}
