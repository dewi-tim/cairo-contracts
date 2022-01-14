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
    account2 = await starknet.deploy(
        "contracts/Account.cairo",
        constructor_calldata=[signer.public_key]
    )

    erc1155 = await starknet.deploy(
        "contracts/token/ERC1155.cairo",
        constructor_calldata=[
            0 # uri
        ]
    )
    return starknet, erc1155, account,account2

#
# Constructor
#

@pytest.mark.asyncio
async def test_constructor(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    execution_info = await erc1155.uri().call()
    assert execution_info.result.uri == 0

#
# ERC165
#

@pytest.mark.asyncio
async def test_supports_interface(erc1155_factory):
    _, erc1155, _,_ = erc1155_factory
    id_ERC165 = int('0x01ffc9a7',16)
    id_IERC1155 = int('0xd9b67a26',16)
    id_IERC1155_MetadataURI = int('0x0e89341c',16)
    id_mandatory_unsupported = int('0xffffffff',16)
    id_random = int('0xaabbccdd',16)
    for supported_id in [id_ERC165,id_IERC1155,id_IERC1155_MetadataURI]:
        execution_info = await erc1155.supportsInterface(
            supported_id
            ).call()
        assert execution_info.result.res == 1
    for unsupported_id in [id_mandatory_unsupported,id_random]:
        execution_info = await erc1155.supportsInterface(
            unsupported_id
            ).call()
        assert execution_info.result.res == 0
    


#
# Set/Get approval
#

@pytest.mark.asyncio
async def test_set_approval_for_all(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    operator = 1
    approval = 1

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'setApprovalForAll',
        [operator,approval]
    )

    execution_info = await erc1155.isApprovedForAll(
        account.contract_address,
        operator
        ).call()
    
    assert execution_info.result.approved == approval

@pytest.mark.asyncio
async def test_set_approval_for_all_non_boolean(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    operator = 2
    approval = 2

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'setApprovalForAll',
        [operator,approval]
    ))


#
# Balance getters
#

@pytest.mark.asyncio
async def test_balance_of_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    token_id = uint(111)
    await assert_revert(erc1155.balanceOf(0,token_id).call())

@pytest.mark.asyncio
async def test_balance_of_batch_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    accounts = [1,0,2]
    token_ids = [111,222,333]
    await assert_revert(erc1155.balanceOfBatch(accounts,token_ids,[0]*3).call())

@pytest.mark.asyncio
async def test_balance_of_batch_uneven_arrays(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    accounts = [1,2,3]
    token_ids = [111,222,333]
    # uneven accounts vs ids
    await assert_revert(erc1155.balanceOfBatch(accounts[:2],token_ids,[0]*3).call())
    await assert_revert(erc1155.balanceOfBatch(accounts,token_ids[:2],[0]*2).call())

    # uneven high vs low id bits
    await assert_revert(erc1155.balanceOfBatch(accounts,token_ids[:2],[0]*3).call())
    await assert_revert(erc1155.balanceOfBatch(accounts,token_ids,[0]*2).call())

#
# Minting
#

@pytest.mark.asyncio
async def test_mint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = account.contract_address
    token_id = uint(111)
    amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *amount, data])

    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == amount

@pytest.mark.asyncio
async def test_mint_to_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 0
    token_id = uint(222)
    data = 0
    amount = uint(1000)

    # minting to 0 address should fail
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *amount, data]
    ))

@pytest.mark.asyncio
async def test_mint_overflow(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 999
    token_id = uint(222)
    data = 0

    # Bring recipient's balance to max possible, should pass (recipient's balance is 0)
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *MAX_UINT256, data]
    )

    # Issuing recipient any more should revert due to overflow
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *uint(1), data]
    ))

    # upon rejection, there should be 0 balance
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == MAX_UINT256
@pytest.mark.asyncio
async def test_mint_invalid_uint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 1111
    token_id = uint(222)
    data = 0

    invalid_amount = (MAX_UINT256[0],MAX_UINT256[1]+1)
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    original_balance = execution_info.result.balance
    assert original_balance == uint(0)
    
    # issuing an invalid uint256 (i.e. either the low or high felts >= 2**128) should revert
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [recipient, *token_id, *invalid_amount, data]
    ))

    # balance should remain 0
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)

# burning
@pytest.mark.asyncio
async def test_burn(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    subject = account.contract_address
    token_id = uint(111)
    amount = uint(2000)

    execution_info = await erc1155.balanceOf(subject,token_id).call()
    original_balance = execution_info.result.balance
    assert original_balance == uint(2000)

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn', [subject, *token_id, *amount])

    execution_info = await erc1155.balanceOf(account.contract_address,token_id).call()
    assert execution_info.result.balance == uint(original_balance[0] - amount[0])

@pytest.mark.asyncio
async def test_burn_from_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    subject = 0
    token_id = uint(111)
    amount = uint(2000)

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn', [subject, *token_id, *amount]))

@pytest.mark.asyncio
async def test_burn_insufficent_balance(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    subject = account.contract_address
    token_id = uint(111)
    amount = uint(2000)

    execution_info = await erc1155.balanceOf(subject,token_id).call()
    original_balance = execution_info.result.balance
    assert original_balance == uint(0)

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn', [subject, *token_id, *amount]))

    execution_info = await erc1155.balanceOf(account.contract_address,token_id).call()
    assert execution_info.result.balance == original_balance

# batch minting
@pytest.mark.asyncio
async def test_mint_batch(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = account.contract_address
    token_ids = [111,222,333]
    amounts = [1000,2000,3000]
    data = 0

    # assumes balances < 2**128
    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low
    assert original_balances == [0]*3

    # mint amount[i] of token_id[i] to recipient
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *uint_array(amounts),data])

    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == [o+a for o,a in zip(original_balances,amounts)]
    assert execution_info.result.batch_balances_high == [0]*3

@pytest.mark.asyncio
async def test_mint_batch_to_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 0
    token_ids = [111,222,333]
    amounts = [1000,2000,3000]
    data = 0

    # mint amount[i] of token_id[i] to recipient
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *uint_array(amounts),data]))

@pytest.mark.asyncio
async def test_mint_batch_overflow(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 999
    token_ids = [444,555,666]
    data = 0
    max_uint_calldata = (3,*[1,MAX_UINT256[0],1],3,*[0,MAX_UINT256[1],0])

    # check token balances initially 0, assumes balances < 2**128
    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low
    assert original_balances == [0]*3

    # Bring 1 recipient's balance to max possible, should pass (recipient's balance is 0)
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *max_uint_calldata, data]
    )

    # Issuing recipient any more on just 1 token_id should revert due to overflow
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids), *uint_array([0,1,0]),data]
    ))

    # balances unchanged since 1st minting
    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    balances = list(zip(
        execution_info.result.batch_balances_low,
        execution_info.result.batch_balances_high
    ))
    assert balances == [uint(1),MAX_UINT256,uint(1)]

@pytest.mark.asyncio
async def test_mint_batch_invalid_uint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 1111
    token_ids = [444,555,666]
    invalid_calldata = uint_array([1,MAX_UINT256[0]+1,1])
    data = 0
    
    # check token balances initially 0
    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    original_balances = list(zip(
        execution_info.result.batch_balances_low,
        execution_info.result.batch_balances_high
    ))
    assert original_balances == [uint(0)]*3

    # attempt passing an invalid uint in batch
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids),*invalid_calldata, data]
    ))

    # balances unchanged since 1st minting <- probably unnecessary
    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids,[0]*3).call()
    balances = list(zip(
        execution_info.result.batch_balances_low,
        execution_info.result.batch_balances_high
    ))
    assert balances == original_balances

@pytest.mark.asyncio
async def test_mint_batch_uneven_arrays(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    recipient = 1111
    amounts = [100,200,300]
    token_ids = [444,555,666]
    
    data = 0

    # uneven token_ids vs amounts
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids),*uint_array(amounts[:2]), data]
    ))
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [recipient, *uint_array(token_ids[:2]),*uint_array(amounts), data]
    ))

    # uneven low vs high bits
    calldata = [
        [recipient, 3,*token_ids,2,*[0]*2,*uint_array(amounts), data],
        [recipient, 2,*token_ids[:2],3,*[0]*3,*uint_array(amounts), data],
        [recipient, *uint_array(token_ids),2,*amounts[:2],3,*[0]*3, data],
        [recipient, *uint_array(token_ids),3,*amounts,2,*[0]*2, data]
    ]
    for cd in calldata:
        await assert_revert(signer.send_transaction(
            account, 
            erc1155.contract_address,
            'mint_batch', cd
        ))
#    
# batch burning
#

@pytest.mark.asyncio
async def test_burn_batch(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = account.contract_address
    token_ids = [111,222,333]
    amounts = [500,1000,1500]
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids), *uint_array(amounts)])
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == [o-a for o,a in zip(original_balances,amounts)]
    assert execution_info.result.batch_balances_high == [0]*3

@pytest.mark.asyncio
async def test_burn_batch_from_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = 0
    token_ids = [111,222,333]
    amounts = [1000,2000,3000]

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids), *uint_array(amounts)]))
   

@pytest.mark.asyncio
async def test_burn_batch_insufficent_balance(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = account.contract_address
    token_ids = [111,222,333]

    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low

    amounts = [original_balances[0],original_balances[1]+1,original_balances[2]]

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids), *uint_array(amounts)]))
    
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == original_balances


@pytest.mark.asyncio
async def test_burn_batch_invalid_uint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = account.contract_address
    token_ids = [111,222,333]
    invalid_calldata = uint_array([1,MAX_UINT256[0]+1,1])
    data = 0
    
    # check token balances initially 0
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    original_balances = list(zip(
        execution_info.result.batch_balances_low,
        execution_info.result.batch_balances_high
    ))

    # attempt passing an invalid uint in batch
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids),*invalid_calldata, data]
    ))

    # balances unchanged since 1st minting <- probably unnecessary
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    balances = list(zip(
        execution_info.result.batch_balances_low,
        execution_info.result.batch_balances_high
    ))
    assert balances == original_balances

@pytest.mark.asyncio
async def test_burn_batch_uneven_array(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = 1111
    amounts = [100,200,300]
    token_ids = [444,555,666]
    
    data = 0

    # uneven token_ids vs amounts
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids),*uint_array(amounts[:2]), data]
    ))
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids[:2]),*uint_array(amounts), data]
    ))

    # uneven low vs high bits
    calldata = [
        [burner, 3,*token_ids,2,*[0]*2,*uint_array(amounts), data],
        [burner, 2,*token_ids[:2],3,*[0]*3,*uint_array(amounts), data],
        [burner, *uint_array(token_ids),2,*amounts[:2],3,*[0]*3, data],
        [burner, *uint_array(token_ids),3,*amounts,2,*[0]*2, data]
    ]
    for cd in calldata:
        await assert_revert(signer.send_transaction(
            account, 
            erc1155.contract_address,
            'burn_batch', cd
        ))
#    
# batch burning
#

@pytest.mark.asyncio
async def test_burn_batch(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    burner = account.contract_address
    token_ids = [111,222,333]
    amounts = [500,1000,1500]
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    original_balances = execution_info.result.batch_balances_low
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'burn_batch', [burner, *uint_array(token_ids), *uint_array(amounts)])
    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids,[0]*3).call()
    assert execution_info.result.batch_balances_low == [o-a for o,a in zip(original_balances,amounts)]
    assert execution_info.result.batch_balances_high == [0]*3

#    
# Transfer
#

@pytest.mark.asyncio
async def test_safe_transfer_from(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 21
    token_id = uint(20)
    amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *amount, data])

    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == amount
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)
    
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *amount, data])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == uint(0)
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == amount

    

@pytest.mark.asyncio
async def test_safe_transfer_from_approved(erc1155_factory):
    starknet, erc1155, account,account2 = erc1155_factory

    

    operator = account.contract_address
    sender = account2.contract_address
    recipient = 23
    token_id = uint(20)
    amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *amount, data])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == amount
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)

    # account2 approves account
    await signer.send_transaction(
        account2, 
        erc1155.contract_address,
        'setApprovalForAll', [operator,1])
    # account sends transaction
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *amount, data])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == uint(0)
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == amount
    
@pytest.mark.asyncio
async def test_safe_transfer_from_invalid_uint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 21
    token_id = uint(21)
    mint_amount = MAX_UINT256
    transfer_amount = (MAX_UINT256[0]+1,0)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *mint_amount, data])
    
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *transfer_amount, data]))
@pytest.mark.asyncio
async def test_safe_transfer_from_insufficient_balance(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 22
    token_id = uint(22)
    mint_amount = uint(1000)
    transfer_amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *mint_amount, data])
    
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *transfer_amount, data]))

@pytest.mark.asyncio
async def test_safe_transfer_from_unapproved(erc1155_factory):
    starknet, erc1155, account, account2 = erc1155_factory

    operator = account.contract_address
    sender = account2.contract_address
    recipient = 24
    token_id = uint(25)
    amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *amount, data])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == amount
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)

    # account2 disapproves account
    await signer.send_transaction(
        account2, 
        erc1155.contract_address,
        'setApprovalForAll', [operator,0])

    # account sends transaction
    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *amount, data]))

    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == amount
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)
    
@pytest.mark.asyncio
async def test_safe_transfer_from_to_zero_address(erc1155_factory):
    starknet, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 21
    token_id = uint(20)
    amount = uint(2000)
    data = 0

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint', [sender, *token_id, *amount, data])
    
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeTransferFrom', [sender, recipient, *token_id, *amount, data])
# Batch Transfer
@pytest.mark.asyncio
async def test_safe_batch_transfer_from(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 40
    token_ids = [31,32,33]
    mint_amounts = [1000,2000,3000]
    transfer_amounts = [500,1000,1500]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *uint_array(mint_amounts),data])

    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data])
    execution_info = await erc1155.balanceOfBatch([sender]*3+[recipient]*3,token_ids*2,[0]*6).call()
    assert execution_info.result.batch_balances_low == [
        m-t for m,t in zip(mint_amounts,transfer_amounts)
    ] + transfer_amounts
    assert execution_info.result.batch_balances_high == [0]*6

@pytest.mark.asyncio
async def test_safe_batch_transfer_from_approved(erc1155_factory):
    _, erc1155, account,account2 = erc1155_factory
    sender = account.contract_address
    operator = account2.contract_address
    recipient = 45
    token_ids = [41,42,43]
    mint_amounts = [1000,2000,3000]
    transfer_amounts = [500,1000,1500]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *uint_array(mint_amounts),data])

    # account approves account2
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'setApprovalForAll', [operator,1])

    await signer.send_transaction(
        account2, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data])
    execution_info = await erc1155.balanceOfBatch([sender]*3+[recipient]*3,token_ids*2,[0]*6).call()
    assert execution_info.result.batch_balances_low == [
        m-t for m,t in zip(mint_amounts,transfer_amounts)
    ] + transfer_amounts
    assert execution_info.result.batch_balances_high == [0]*6


@pytest.mark.asyncio
async def test_safe_batch_transfer_from_invalid_uint(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 50
    token_ids = [51,52,53]
    mint_amounts_hi = [MAX_UINT256[0]]*3
    mint_amounts_lo = mint_amounts_hi 
    mint_amounts_calldata = (3,*mint_amounts_lo,3,*mint_amounts_hi)
    transfer_amounts = [500,MAX_UINT256[0]+1,1500]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *mint_amounts_calldata,data])

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data]))


@pytest.mark.asyncio
async def test_safe_batch_transfer_from_insufficient_balance(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 50
    token_ids = [61,62,63]
    mint_amounts = [100]*3
    transfer_amounts = [50,101,50]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *uint_array(mint_amounts),data])

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data]))

@pytest.mark.asyncio
async def test_safe_batch_transfer_from_unapproved(erc1155_factory):
    _, erc1155, account,account2 = erc1155_factory
    sender = account.contract_address
    non_operator = account2.contract_address
    recipient = 70
    token_ids = [71,72,73]
    mint_amounts = [1000,2000,3000]
    transfer_amounts = [500,1000,1500]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *uint_array(mint_amounts),data])
    # account disapproves account2
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'setApprovalForAll', [non_operator,0])

    await assert_revert(signer.send_transaction(
        account2, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data]))

@pytest.mark.asyncio
async def test_safe_batch_transfer_from_to_zero_address(erc1155_factory):
    _, erc1155, account,_ = erc1155_factory
    _, erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = 0
    token_ids = [31,32,33]
    mint_amounts = [1000,2000,3000]
    transfer_amounts = [500,1000,1500]
    data = 0

    # mint amount[i] of token_id[i] to sender
    await signer.send_transaction(
        account, 
        erc1155.contract_address,
        'mint_batch', [sender, *uint_array(token_ids), *uint_array(mint_amounts),data])

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uint_array(token_ids), *uint_array(transfer_amounts),data]))
    

