import pytest
import asyncio
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starknet.testing.starknet import Starknet, StarknetContract
from utils import Signer, uint, uarr2cd, uint_array, str_to_felt, MAX_UINT256, assert_revert

signer = Signer(123456789987654321)
account_path = 'contracts/Account.cairo'
erc1155_path = 'contracts/token/ERC1155.cairo'

#
# Parameters/aliases
#

TRUE = 1
FALSE = 0
NON_BOOLEAN = 2
ZERO_ADDRESS = 0

DATA = []

ACCOUNT = 123
TOKEN_ID = uint(111)
MINT_AMOUNT = uint(1000)
BURN_AMOUNT = uint(500)
TRANSFER_AMOUNT = uint(500)
INVALID_UINT = uint(MAX_UINT256[0]+1)

ACCOUNTS = [123,234,345]
TOKEN_IDS = uint_array([111,222,333])
MINT_AMOUNTS = uint_array([1000,2000,3000])
BURN_AMOUNTS = uint_array([500,1000,1500])
TRANSFER_AMOUNTS = uint_array([500,1000,1500])
TRANSFER_DIFFERENCE = [uint(m[0]-t[0]) for m,t in zip(MINT_AMOUNTS,TRANSFER_AMOUNTS)]
INVALID_AMOUNTS = uint_array([1,MAX_UINT256[0]+1,1])
INVALID_IDS = uint_array([111,MAX_UINT256[0]+1,333])

MAX_UINT_AMOUNTS = [uint(1),MAX_UINT256,uint(1)]

id_ERC165 = int('0x01ffc9a7',16)
id_IERC1155 = int('0xd9b67a26',16)
id_IERC1155_MetadataURI = int('0x0e89341c',16)
id_mandatory_unsupported = int('0xffffffff',16)
id_random = int('0xaabbccdd',16)

SUPPORTED_INTERFACES = [id_ERC165,id_IERC1155,id_IERC1155_MetadataURI]
UNSUPPORTED_INTERFACES = [id_mandatory_unsupported,id_random]



@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_defs():
    account_def = compile_starknet_files(
        files=[account_path], 
        debug_info=True
    )
    erc1155_def = compile_starknet_files(
        files=[erc1155_path], 
        debug_info=True
    )
    return account_def,erc1155_def
    
@pytest.fixture(scope='module')
async def erc1155_init(contract_defs):
    account_def,erc1155_def = contract_defs
    starknet = await Starknet.empty()
    account1 = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[signer.public_key]
    )
    account2 = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[signer.public_key]
    )
    erc1155 = await starknet.deploy(
        contract_def=erc1155_def,
        constructor_calldata=[0]
    )
    return (
        starknet.state,
        account1,
        account2,
        erc1155
    )

@pytest.fixture
def erc1155_factory(contract_defs,erc1155_init):
    account_def,erc1155_def = contract_defs
    state,account1,account2,erc1155 = erc1155_init
    _state = state.copy()
    account1 = StarknetContract(
        state=_state,
        abi=account_def.abi,
        contract_address=account1.contract_address,
        deploy_execution_info=account1.deploy_execution_info
    )
    account2 = StarknetContract(
        state=_state,
        abi=account_def.abi,
        contract_address=account2.contract_address,
        deploy_execution_info=account2.deploy_execution_info
    )
    erc1155 = StarknetContract(
        state=_state,
        abi=erc1155_def.abi,
        contract_address=erc1155.contract_address,
        deploy_execution_info=erc1155.deploy_execution_info
    )
    return erc1155,account1,account2
#
# Constructor
#

@pytest.mark.asyncio
async def test_constructor(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    execution_info = await erc1155.uri().call()
    assert execution_info.result.uri == 0

#
# ERC165
#

@pytest.mark.asyncio
async def test_supports_interface(erc1155_factory):
    erc1155, _,_ = erc1155_factory
    
    for supported_id in SUPPORTED_INTERFACES:
        execution_info = await erc1155.supportsInterface(
            supported_id
            ).call()
        assert execution_info.result.res == TRUE

    for unsupported_id in UNSUPPORTED_INTERFACES:
        execution_info = await erc1155.supportsInterface(
            unsupported_id
            ).call()
        assert execution_info.result.res == FALSE

#
# Set/Get approval
#

@pytest.mark.asyncio
async def test_set_approval_for_all(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    operator = ACCOUNT
    approval = TRUE

    await signer.send_transaction(
        account, erc1155.contract_address,'setApprovalForAll',
        [operator,approval]
    )

    execution_info = await erc1155.isApprovedForAll(
        account.contract_address,
        operator
    ).call()
    
    assert execution_info.result.approved == approval

    operator = ACCOUNT
    approval = FALSE

    await signer.send_transaction(
        account, erc1155.contract_address,'setApprovalForAll',
        [operator,approval]
    )

    execution_info = await erc1155.isApprovedForAll(
        account.contract_address,
        operator
    ).call()
    
    assert execution_info.result.approved == approval

@pytest.mark.asyncio
async def test_set_approval_for_all_non_boolean(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    operator = ACCOUNT
    approval = NON_BOOLEAN

    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'setApprovalForAll',
        [operator,approval]
    ))


#
# Balance getters
#

@pytest.mark.asyncio
async def test_balance_of_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    await assert_revert(erc1155.balanceOf(ZERO_ADDRESS,TOKEN_ID).invoke())

@pytest.mark.asyncio
async def test_balance_of_batch_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    accounts = [ACCOUNT,ZERO_ADDRESS,ACCOUNT]

    await assert_revert(erc1155.balanceOfBatch(accounts,TOKEN_IDS).invoke())

@pytest.mark.asyncio
async def test_balance_of_batch_uneven_arrays(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    accounts = ACCOUNTS
    ids = TOKEN_IDS

    # len(accounts) != len(ids)
    await assert_revert(erc1155.balanceOfBatch(accounts[:2],ids).call())
    await assert_revert(erc1155.balanceOfBatch(accounts,ids[:2]).call())

#
# Minting
#

@pytest.mark.asyncio
async def test_mint(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ACCOUNT
    token_id = TOKEN_ID
    amount = MINT_AMOUNT
    
    await erc1155.mint(recipient,token_id,amount,DATA).invoke()

    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == amount

@pytest.mark.asyncio
async def test_mint_to_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ZERO_ADDRESS
    token_id = TOKEN_ID
    amount = MINT_AMOUNT

    # minting to 0 address should fail
    await assert_revert(
        erc1155.mint(
            recipient,token_id,amount,DATA
        ).invoke()
    )

@pytest.mark.asyncio
async def test_mint_overflow(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ACCOUNT
    token_id = TOKEN_ID
    
    # Bring recipient's balance to max possible, should pass (recipient's balance is 0)
    amount = MAX_UINT256
    await erc1155.mint(recipient,token_id,amount,DATA).invoke()

    # Issuing recipient any more should revert due to overflow
    amount = uint(1)
    await assert_revert(
        erc1155.mint(recipient,token_id,amount,DATA).invoke()
    )

    # upon rejection, there should be 0 balance
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == MAX_UINT256

@pytest.mark.asyncio
async def test_mint_invalid_uint(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ACCOUNT
    token_id = TOKEN_ID
    invalid_amount = INVALID_UINT

    # issuing an invalid uint256 (i.e. either the low or high felts >= 2**128) should revert
    await assert_revert(
        erc1155.mint(recipient,token_id,invalid_amount,DATA).invoke()
    )

    # balance should remain 0 <- redundant
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == uint(0)

#
# Burning
#

@pytest.mark.asyncio
async def test_burn(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    subject = account.contract_address
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    burn_amount = BURN_AMOUNT

    await erc1155.mint(subject,token_id,mint_amount,DATA).invoke()

    await erc1155.burn(subject,token_id,burn_amount).invoke()

    execution_info = await erc1155.balanceOf(subject,token_id).call()
    assert execution_info.result.balance == uint(mint_amount[0] - burn_amount[0])

@pytest.mark.asyncio
async def test_burn_from_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    subject = ZERO_ADDRESS
    token_id = TOKEN_ID
    # TODO burn nonzero too
    amount = uint(0)

    await assert_revert(
        erc1155.burn(subject,token_id,amount).invoke()
    )

@pytest.mark.asyncio
async def test_burn_insufficient_balance(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    subject = account.contract_address
    token_id = TOKEN_ID
    amount = BURN_AMOUNT

    # Burn non-0 amount w/ 0 balance
    await assert_revert(
        erc1155.burn(subject,token_id,amount).invoke()
    )

    # additionally mint then burn

# batch minting
@pytest.mark.asyncio
async def test_mint_batch(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    recipient = account.contract_address
    token_ids = TOKEN_IDS
    amounts = MINT_AMOUNTS

    # mint amount[i] of token_id[i] to recipient
    await erc1155.mint_batch(recipient,token_ids,amounts,DATA).invoke()

    execution_info = await erc1155.balanceOfBatch([recipient]*3,token_ids).call()
    assert execution_info.result.batch_balances == amounts

@pytest.mark.asyncio
async def test_mint_batch_to_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ZERO_ADDRESS
    token_ids = TOKEN_IDS
    amounts = MINT_AMOUNTS
    
    # mint amount[i] of token_id[i] to recipient
    await assert_revert(
        erc1155.mint_batch(recipient,token_ids,amounts,DATA).invoke()
    )

@pytest.mark.asyncio
async def test_mint_batch_overflow(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    max_amounts = MAX_UINT_AMOUNTS

    # Bring 1 recipient's balance to max possible, should pass (recipient's balance is 0)
    await erc1155.mint_batch(recipient,token_ids,max_amounts,DATA).invoke()
    
    # Issuing recipient any more on just 1 token_id should revert due to overflow
    amounts = uint_array([0,1,0])
    await assert_revert(
        erc1155.mint_batch(recipient,token_ids,amounts,DATA).invoke()
    )



@pytest.mark.asyncio
async def test_mint_batch_invalid_uint(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    invalid_ids = INVALID_IDS
    amounts = MINT_AMOUNTS
    invalid_amounts = INVALID_AMOUNTS
    
    # attempt passing an invalid amount in batch
    await assert_revert(
        erc1155.mint_batch(recipient,token_ids,invalid_amounts,DATA).invoke()
    )

     # attempt passing an invalid id in batch
    await assert_revert(
        erc1155.mint_batch(recipient,invalid_ids,amounts,DATA).invoke()
    )


@pytest.mark.asyncio
async def test_mint_batch_uneven_arrays(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    amounts = MINT_AMOUNTS
    
    # uneven token_ids vs amounts
    await assert_revert(
        erc1155.mint_batch(recipient,token_ids,amounts[:2],DATA).invoke()
    )

    await assert_revert(
        erc1155.mint_batch(recipient,token_ids[:2],amounts,DATA).invoke()
    )
#    
# batch burning
#

@pytest.mark.asyncio
async def test_burn_batch(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    burner = account.contract_address
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    burn_amounts = BURN_AMOUNTS

    await erc1155.mint_batch(burner,token_ids,mint_amounts,DATA).invoke()
    
    await erc1155.burn_batch(burner,token_ids,burn_amounts).invoke()

    execution_info = await erc1155.balanceOfBatch([burner]*3,token_ids).call()
    assert execution_info.result.batch_balances == [uint(m[0]-b[0]) for m,b in zip(mint_amounts,burn_amounts)]

@pytest.mark.asyncio
async def test_burn_batch_from_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    burner = ZERO_ADDRESS
    token_ids = TOKEN_IDS
    amounts = [uint(0)]*3
    

    # Attempt to burn nothing (since cannot mint non_zero balance to burn)
    await assert_revert(
        erc1155.burn_batch(burner,token_ids,amounts).invoke()
    )
   

@pytest.mark.asyncio
async def test_burn_batch_insufficent_balance(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    burner = account.contract_address
    token_ids = TOKEN_IDS
    amounts = BURN_AMOUNTS

    await assert_revert(
        erc1155.burn_batch(burner,token_ids,amounts).invoke()
    )
    
    # todo nonzero balance
@pytest.mark.asyncio
async def test_burn_batch_invalid_uint(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    burner = account.contract_address
    token_ids = TOKEN_IDS
    mint_amounts = MAX_UINT_AMOUNTS
    burn_amounts = INVALID_AMOUNTS

    await erc1155.mint_batch(burner,token_ids,mint_amounts,DATA).invoke()

    # attempt passing an invalid uint in batch
    await assert_revert(
        erc1155.burn_batch(burner,token_ids,burn_amounts).invoke()
    )

@pytest.mark.asyncio
async def test_burn_batch_uneven_arrays(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    burner = ACCOUNT
    mint_amounts = MINT_AMOUNTS
    burn_amounts = BURN_AMOUNTS
    token_ids = TOKEN_IDS

    await erc1155.mint_batch(burner,token_ids,mint_amounts,DATA).invoke()

    # uneven token_ids vs amounts
    await assert_revert(
        erc1155.burn_batch(burner,token_ids,burn_amounts[:2]).invoke()
    )
    await assert_revert(
        erc1155.burn_batch(burner,token_ids[:2],burn_amounts).invoke()
    )


#    
# Transfer
#

@pytest.mark.asyncio
async def test_safe_transfer_from(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = TRANSFER_AMOUNT
    

    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()
    
    await signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *transfer_amount, 0])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == uint(mint_amount[0]-transfer_amount[0])
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == transfer_amount

    

@pytest.mark.asyncio
async def test_safe_transfer_from_approved(erc1155_factory):
    erc1155, account,account2 = erc1155_factory

    operator = account.contract_address
    sender = account2.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = TRANSFER_AMOUNT
    approval = TRUE
    

    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()

    # account2 approves account
    await signer.send_transaction(
        account2, erc1155.contract_address,'setApprovalForAll',
        [operator,approval])

    # account sends transaction
    await signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *transfer_amount, 0])
    
    execution_info = await erc1155.balanceOf(sender,token_id).call()
    assert execution_info.result.balance == uint(mint_amount[0]-transfer_amount[0])
    execution_info = await erc1155.balanceOf(recipient,token_id).call()
    assert execution_info.result.balance == transfer_amount
    
@pytest.mark.asyncio
async def test_safe_transfer_from_invalid_uint(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    invalid_id = INVALID_UINT
    mint_amount = MAX_UINT256
    transfer_amount = TRANSFER_AMOUNT
    invalid_amount = INVALID_UINT
    
    # mint max uint to avoid possible insufficient balance error
    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()
    
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *invalid_amount, 0]))
    # transfer 0 amount
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *invalid_id, *transfer_amount, 0]))

@pytest.mark.asyncio
async def test_safe_transfer_from_insufficient_balance(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = uint(MINT_AMOUNT[0]+1)
    
    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()
    
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *transfer_amount, 0]))

@pytest.mark.asyncio
async def test_safe_transfer_from_unapproved(erc1155_factory):
    erc1155, account, account2 = erc1155_factory

    operator = account.contract_address
    sender = account2.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = TRANSFER_AMOUNT 
    approval = FALSE

    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()

    # account2 disapproves account <- redundant
    await signer.send_transaction(
        account2, erc1155.contract_address,'setApprovalForAll',
        [operator,approval])

    # account sends transaction, should fail
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *transfer_amount, 0]))

# @pytest.mark.asyncio
# async def test_safe_transfer_from_from_zero_address(erc1155_factory):
#     erc1155, account, _ = erc1155_factory

#     sender = ZERO_ADDRESS
#     approval = TRUE
#     recipient = ACCOUNT
#     token_id = TOKEN_ID
#     transfer_amount = uint(0)
    

#     # Caller address is `0` when not using an account contract
#     await assert_revert(
#         erc1155.safeTransferFrom(
#             sender,
#             recipient,
#             token_id,
#             transfer_amount,
#             []
#         ).invoke()
#     )
    
@pytest.mark.asyncio
async def test_safe_transfer_from_to_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ZERO_ADDRESS
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = TRANSFER_AMOUNT
    

    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()

    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeTransferFrom',
        [sender, recipient, *token_id, *transfer_amount, 0]))

@pytest.mark.asyncio
async def test_safe_transfer_from_overflow(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_id = TOKEN_ID
    mint_amount = MINT_AMOUNT
    transfer_amount = TRANSFER_AMOUNT
    max_amount = MAX_UINT256

    await erc1155.mint(sender,token_id,mint_amount,DATA).invoke()

    # Bring recipient's balance to max possible, should pass (recipient's balance is 0)
    await erc1155.mint(recipient,token_id,max_amount,DATA).invoke()


    # Issuing recipient any more should revert due to overflow
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address, 'safeTransferFrom',
        [sender,recipient, *token_id, *transfer_amount, 0]
    ))


# Batch Transfer
@pytest.mark.asyncio
async def test_safe_batch_transfer_from(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS
    difference = TRANSFER_DIFFERENCE

    # mint amount[i] of token_id[i] to sender
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    await signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0])

    execution_info = await erc1155.balanceOfBatch([sender]*3+[recipient]*3,token_ids*2).call()
    assert execution_info.result.batch_balances[:3] == difference
    assert execution_info.result.batch_balances[3:] == transfer_amounts


@pytest.mark.asyncio
async def test_safe_batch_transfer_from_approved(erc1155_factory):
    erc1155, account,account2 = erc1155_factory

    sender = account.contract_address
    operator = account2.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS
    difference = TRANSFER_DIFFERENCE
    approval = TRUE
    
    # mint amount[i] of token_id[i] to sender
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    # account approves account2
    await signer.send_transaction(
        account, erc1155.contract_address,'setApprovalForAll',
        [operator,approval])

    await signer.send_transaction(
        account2, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0])
   
    execution_info = await erc1155.balanceOfBatch([sender]*3+[recipient]*3,token_ids*2).call()
    assert execution_info.result.batch_balances[:3] == difference
    assert execution_info.result.batch_balances[3:] == transfer_amounts



@pytest.mark.asyncio
async def test_safe_batch_transfer_from_invalid_uint(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    invalid_ids = INVALID_IDS
    mint_amounts = MAX_UINT_AMOUNTS
    invalid_amounts = INVALID_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS

    # mint amount[i] of token_id[i] to sender
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(token_ids), *uarr2cd(invalid_amounts),0]))
    # attempt transfer 0 due to insufficient balance error
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(invalid_ids), *uarr2cd(transfer_amounts),0]))


@pytest.mark.asyncio
async def test_safe_batch_transfer_from_insufficient_balance(erc1155_factory):
    erc1155, account,_ = erc1155_factory
    sender = account.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    transfer_amounts = TRANSFER_AMOUNTS

    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0]))

@pytest.mark.asyncio
async def test_safe_batch_transfer_from_unapproved(erc1155_factory):
    erc1155, account,account2 = erc1155_factory

    sender = account.contract_address
    operator = account2.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS
    approval = FALSE
    

    # mint amount[i] of token_id[i] to sender
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    # account disapproves account2 (redundant)
    await signer.send_transaction(
        account, erc1155.contract_address,'setApprovalForAll',
        [operator,approval])

    await assert_revert(signer.send_transaction(
        account2, erc1155.contract_address,'safeBatchTransferFrom',
        [sender,recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0]))
   

@pytest.mark.asyncio
async def test_safe_batch_transfer_from_to_zero_address(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ZERO_ADDRESS
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS
    

    # mint amount[i] of token_id[i] to sender
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    await assert_revert(signer.send_transaction(
        account, 
        erc1155.contract_address,
        'safeBatchTransferFrom', [sender,recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0]))
    
@pytest.mark.asyncio
async def test_safe_batch_transfer_from_uneven_arrays(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    mint_amounts = MINT_AMOUNTS
    transfer_amounts = TRANSFER_AMOUNTS
    token_ids = TOKEN_IDS

    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    # uneven token_ids vs amounts
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender, recipient, *uarr2cd(token_ids),*uarr2cd(transfer_amounts[:2]), 0]
    ))
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [sender, recipient, *uarr2cd(token_ids[:2]),*uarr2cd(transfer_amounts), 0]
    ))


@pytest.mark.asyncio
async def test_safe_batch_transfer_from_overflow(erc1155_factory):
    erc1155, account,_ = erc1155_factory

    sender = account.contract_address
    recipient = ACCOUNT
    token_ids = TOKEN_IDS
    mint_amounts = MINT_AMOUNTS
    max_amounts = MAX_UINT_AMOUNTS
    transfer_amounts = uint_array([0,1,0])

    # give sender some money
    await erc1155.mint_batch(sender,token_ids,mint_amounts,DATA).invoke()

    # Bring 1 recipient's balance to max possible, should pass (recipient's balance is 0)
    await signer.send_transaction(
        account, erc1155.contract_address,'mint_batch', 
        [recipient, *uarr2cd(token_ids), *uarr2cd(max_amounts), 0]
    )
    
    # Issuing recipient any more on just 1 token_id should revert due to overflow
    await assert_revert(signer.send_transaction(
        account, erc1155.contract_address,'safeBatchTransferFrom',
        [recipient, *uarr2cd(token_ids), *uarr2cd(transfer_amounts),0]
    ))
