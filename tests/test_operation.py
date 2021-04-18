import pytest
from brownie import Wei, accounts, chain

# reference code taken from yHegic repo and stecrv strat
# https://github.com/Macarse/yhegic
# https://github.com/Grandthrax/yearnv2_steth_crv_strat

# Amount configs, shared between tests
test_budget = Wei("888000 ether")
approve_amount = Wei("1000000 ether")
deposit_limit = Wei("889000 ether")
bob_deposit = Wei("100000 ether")
alice_deposit = Wei("788000 ether")


def test_operation(
    currency,
    strategy,
    chain,
    vault,
    whale,
    gov,
    bob,
    alice,
    strategist,
    guardian,
    interface,
):
    currency.approve(whale, approve_amount, {"from": whale})
    currency.transferFrom(whale, gov, test_budget, {"from": whale})

    vault.setDepositLimit(deposit_limit)

    # 100% of the vault's depositLimit
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 0, {"from": gov})

    currency.approve(gov, approve_amount, {"from": gov})
    currency.transferFrom(gov, bob, bob_deposit, {"from": gov})
    currency.transferFrom(gov, alice, alice_deposit, {"from": gov})
    currency.approve(vault, approve_amount, {"from": bob})
    currency.approve(vault, approve_amount, {"from": alice})

    vault.deposit(bob_deposit, {"from": bob})
    vault.deposit(alice_deposit, {"from": alice})
    # Sleep and harvest 5 times
    sleepAndHarvest(5, strategy, gov)
    # We should have made profit or stayed stagnant (This happens when there is no rewards in 1INCH rewards)
    assert vault.pricePerShare() / 1e18 >= 1
    # Withdraws should not fail
    vault.withdraw(alice_deposit, {"from": alice})
    vault.withdraw(bob_deposit, {"from": bob})

    # Depositors after withdraw should have a profit or gotten the original amount
    assert currency.balanceOf(alice) >= alice_deposit
    assert currency.balanceOf(bob) >= bob_deposit

    # Make sure it isnt less than 1 after depositors withdrew
    assert vault.pricePerShare() / 1e18 >= 1


def test_operation_internal(
    currencyfUSDTLP,
    strategyFUSDTLP,
    chain,
    vaultFUSDTLP,
    whalefusdtlp,
    gov,
    bob,
    alice,
    strategist,
    guardian,
    interface,
):
    currencyfUSDTLP.approve(whalefusdtlp, approve_amount, {"from": whalefusdtlp})
    currencyfUSDTLP.transfer(gov, test_budget, {"from": whalefusdtlp})

    vaultFUSDTLP.setDepositLimit(deposit_limit)

    # 100% of the vault's depositLimit
    vaultFUSDTLP.addStrategy(strategyFUSDTLP, 10_000, 0, 2 ** 256 - 1, 0, {"from": gov})

    currencyfUSDTLP.transfer(bob, bob_deposit, {"from": gov})
    currencyfUSDTLP.transfer(alice, alice_deposit, {"from": gov})
    currencyfUSDTLP.approve(vaultFUSDTLP, approve_amount, {"from": bob})
    currencyfUSDTLP.approve(vaultFUSDTLP, approve_amount, {"from": alice})

    vaultFUSDTLP.deposit(bob_deposit, {"from": bob})
    vaultFUSDTLP.deposit(alice_deposit, {"from": alice})
    # Sleep and harvest 5 times
    sleepAndHarvest(5, strategyFUSDTLP, gov)
    # We should have made profit or stayed stagnant (This happens when there is no rewards in 1INCH rewards)
    assert vaultFUSDTLP.pricePerShare() / 1e18 >= 1
    # Withdraws should not fail
    vaultFUSDTLP.withdraw(alice_deposit, {"from": alice})
    vaultFUSDTLP.withdraw(bob_deposit, {"from": bob})

    # Depositors after withdraw should have a profit or gotten the original amount
    assert currencyfUSDTLP.balanceOf(alice) >= alice_deposit
    assert currencyfUSDTLP.balanceOf(bob) >= bob_deposit

    # Make sure it isnt less than 1 after depositors withdrew
    assert vaultFUSDTLP.pricePerShare() / 1e18 >= 1


def sleepAndHarvest(times, strat, gov):
    for i in range(times):
        debugStratData(strat, "Before harvest" + str(i))
        chain.sleep(2500)
        chain.mine(1)
        strat.harvest({"from": gov})
        debugStratData(strat, "After harvest" + str(i))


# Used to debug strategy balance data
def debugStratData(strategy, msg):
    print(msg)
    print("Total assets " + str(strategy.estimatedTotalAssets()))
    print("1INCH Balance " + str(strategy.balanceOfWant()))
    print("Stake balance " + str(strategy.balanceOfStake()))
    print("Pending reward " + str(strategy.pendingReward()))
