import pytest
from brownie import config, Strategy, StrategyfUSDT, Contract, accounts

fixtures = "currency", "whale", "strategyBase"
params = [
    pytest.param(
        "0xaF4dE8E872131AE328Ce21D909C74705d3Aaf452",
        "0xcce949De564fE60e7f96C85e55177F8B9E4CF61b",
        Strategy,
        id="3EPS",
    ),
    pytest.param(
        "0x373410A99B64B089DFE16F1088526D399252dacE",
        "0xAa9E20bAb58d013220D632874e9Fe44F8F971e4d",
        StrategyfUSDT,
        id="fUSDTLP",
    ),
]


@pytest.fixture
def andre(accounts):
    # Andre, giver of tokens, and maker of yield
    yield accounts[0]


@pytest.fixture
def gov(accounts):
    # yearn multis... I mean YFI governance. I swear!
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]


@pytest.fixture
def strategist(accounts):
    # You! Our new Strategist!
    yield accounts[3]


@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]


@pytest.fixture
def bob(accounts):
    yield accounts[5]


@pytest.fixture
def alice(accounts):
    yield accounts[6]


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract


@pytest.fixture
def currency(request):
    # this one is 3EPS
    yield Contract.from_explorer(request.param)


@pytest.fixture
def currencyfUSDTLP(interface):
    # this one is fUSDT3EPS LP
    yield interface.ERC20("0x373410A99B64B089DFE16F1088526D399252dacE")


@pytest.fixture
def whale(request, currency, currencyfUSDTLP):
    acc = accounts.at(request.param, force=True)
    requiredBal = 100_000_100 * 1e18
    if currency.balanceOf(acc) < requiredBal and currency == currencyfUSDTLP:
        minter = accounts.at("0x556ea0b4c06D043806859c9490072FaadC104b63", force=True)
        currency.mint(acc, requiredBal, {"from": minter})
    yield acc


@pytest.fixture
def vault(pm, gov, rewards, guardian, currency):
    Vault = pm(config["dependencies"][0]).Vault
    vault = gov.deploy(Vault)
    vault.initialize(currency, gov, rewards, "", "", guardian)
    vault.setManagementFee(0, {"from": gov})
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    yield vault


@pytest.fixture
def strategyBase(request):
    yield request.param


@pytest.fixture
def strategy(strategist, keeper, vault, strategyBase):
    strategy = strategist.deploy(strategyBase, vault)
    strategy.setKeeper(keeper)
    yield strategy
