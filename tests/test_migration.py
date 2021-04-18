import pytest

from brownie import Wei, chain

deposit_amount = Wei("100 ether")


def test_migrate(
    currency, Strategy, strategy, chain, vault, whale, gov, strategist, interface
):
    debt_ratio = 10_000
    vault.addStrategy(strategy, debt_ratio, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    currency.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(deposit_amount, {"from": whale})
    strategy.harvest({"from": strategist})

    chain.sleep(2592000)
    chain.mine(1)

    strategy.harvest({"from": strategist})
    totalasset_beforemig = strategy.estimatedTotalAssets()
    assert totalasset_beforemig > 0

    strategy2 = strategist.deploy(Strategy, vault)
    vault.migrateStrategy(strategy, strategy2, {"from": gov})
    # Check that we got all the funds on migration + any reward additions
    assert strategy2.estimatedTotalAssets() >= totalasset_beforemig


def test_migrate_fusdt(
    currencyfUSDTLP,
    StrategyfUSDT,
    strategyFUSDTLP,
    chain,
    vaultFUSDTLP,
    whalefUSDTLP,
    gov,
    strategist,
    interface,
):
    debt_ratio = 10_000
    vaultFUSDTLP.addStrategy(
        strategyFUSDTLP, debt_ratio, 0, 2 ** 256 - 1, 1_000, {"from": gov}
    )

    currencyfUSDTLP.approve(vaultFUSDTLP, 2 ** 256 - 1, {"from": whalefUSDTLP})
    vaultFUSDTLP.deposit(deposit_amount, {"from": whalefUSDTLP})
    strategyFUSDTLP.harvest({"from": strategist})

    chain.sleep(2592000)
    chain.mine(1)

    strategyFUSDTLP.harvest({"from": strategist})
    totalasset_beforemig = strategyFUSDTLP.estimatedTotalAssets()
    assert totalasset_beforemig > 0

    strategy2 = strategist.deploy(StrategyfUSDT, vaultFUSDTLP)
    vaultFUSDTLP.migrateStrategy(strategyFUSDTLP, strategy2, {"from": gov})
    # Check that we got all the funds on migration + any reward additions
    assert strategy2.estimatedTotalAssets() >= totalasset_beforemig
