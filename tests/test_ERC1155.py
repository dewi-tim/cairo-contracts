import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils import Signer, uint, uint_array, str_to_felt, MAX_UINT256, assert_revert

signer = Signer(123456789987654321)

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def erc1155_factory():
    starknet = await Starknet.empty()
    account = await starknet.deploy(
        "contracts/Account.cairo",
        constructor_calldata=[signer.public_key]
    )

    erc1155 = await starknet.deploy(
        "contracts/token/ERC1155.cairo",
        constructor_calldata=[
            0 # uri
        ]
    )
    return starknet, erc1155, account

@pytest.mark.asyncio
async def test_constructor(erc1155_factory):
    _, erc1155, account = erc1155_factory
    execution_info = await erc1155.uri().call()
    assert execution_info.result.uri == 0

@pytest.mark.asyncio
async def test_mint(erc1155_factory):
    _, erc1155, account = erc1155_factory
    recipient = account.contract_address
    token_id = uint(111)
    amount = uint(1000)
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *amount])
    execution_info = await erc1155.balanceOf(account.contract_address,token_id).call()
    assert execution_info.result.balance == amount

@pytest.mark.asyncio
async def test_mint_batch(erc1155_factory):
    _, erc1155, account = erc1155_factory
    recipient = account.contract_address
    recipients = [recipient]*3
    token_ids = [111,222,333]
    amounts = [1000,2000,3000]
    execution_info = await erc1155.balanceOfBatch(recipients,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *uint_array(amounts)])
    execution_info = await erc1155.balanceOfBatch(recipients,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == [o+a for o,a in zip(original_balances,amounts)]
    assert execution_info.result.batch_balances_high == [0]*3

@pytest.mark.asyncio
async def test_burn(erc1155_factory):
    _, erc1155, account = erc1155_factory
    subject = account.contract_address
    token_id = uint(111)
    amount = uint(1000)
    execution_info = await erc1155.balanceOf(account.contract_address,token_id).call()
    original_balance = execution_info.result.balance
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn', [subject, *token_id, *amount])
    execution_info = await erc1155.balanceOf(account.contract_address,token_id).call()
    assert execution_info.result.balance == uint(original_balance[0] - amount[0])

@pytest.mark.asyncio
async def test_burn_batch(erc1155_factory):
    _, erc1155, account = erc1155_factory
    recipient = account.contract_address
    recipients = [recipient]*3
    token_ids = [111,222,333]
    amounts = [1000,2000,3000]
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *uint_array(amounts)])
    execution_info = await erc1155.balanceOfBatch(recipients,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == [amounts[0] + 1000,*amounts[1:]]
    assert execution_info.result.batch_balances_high == [0]*3






