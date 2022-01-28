%lang starknet

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_check)


# Notes: does not implement "data" arguments or do(Batch)SafeTransferAcceptanceCheck until account contracts can be distinguished and hook overriding resolve
# TODO make sure all uint inputs are checked
const IERC1155_interface_id = 0xd9b67a26
const IERC1155_MetadataURI_interface_id = 0x0e89341c
const IERC165_interface_id = 0x01ffc9a7


#
# Events
#

@event
func TransferSingle(
        operator : felt, from_ : felt, to : felt, id : Uint256, value : Uint256):
end

@event
func TransferBatch(
        operator : felt, from_ : felt, to : felt, 
        ids_len : felt, ids : Uint256*, 
        values_len : felt, values : Uint256*):
end

@event
func ApprovalForAll(
        account : felt, operator : felt, approved : felt):
end

@event
func URI(
        value_len : felt, value : felt*, id : Uint256):
end


#
# Storage
#

@storage_var
func _balances(id : Uint256, account : felt) -> (balance : Uint256):
end

@storage_var
func _operator_approvals(account : felt, operator : felt) -> (approved : felt):
end

# TODO: decide URI format
@storage_var
func _uri() -> (uri : felt):
end

#
# Constructor
#

func ERC1155_initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        uri_ : felt):
    _setURI(uri_)
    return ()
end

#
# View
#

func ERC1155_supports_interface(interface_id : felt) -> (res : felt):
    if interface_id == IERC1155_interface_id:
        return (1)
    end
    if interface_id == IERC1155_MetadataURI_interface_id:
        return (1)
    end
    if interface_id == IERC165_interface_id:
        return (1)
    end
    return (0)
end


func ERC1155_uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (uri : felt):
    let (uri) = _uri.read()
    return (uri)
end


func ERC1155_balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, id : Uint256) -> (balance : Uint256):
    assert_not_zero(account)
    let (balance) = _balances.read(id=id, account=account)
    return (balance)
end


func ERC1155_balance_of_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*) -> (
        batch_balances_len : felt, batch_balances : Uint256*):
    alloc_locals
    # Check args are equal length arrays
    assert ids_len = accounts_len
    # Allocate memory
    let (local batch_balances : Uint256*) = alloc()
    let batch_balances_len = accounts_len
    # Call iterator
    balance_of_batch_iter(
        accounts_len,
        accounts,
        ids_len,
        ids,
        batch_balances_len,
        batch_balances)
    let batch_balances_len = accounts_len
    return (
        batch_balances_len, batch_balances)
end


func ERC1155_is_approved_for_all{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, operator : felt) -> (approved : felt):
    let (approved) = _operator_approvals.read(account=account, operator=operator)
    return (approved)
end


#
# Externals
#

func ERC1155_set_approval_for_all{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        operator : felt, approved : felt):
    let (caller) = get_caller_address()
    _set_approval_for_all(owner=caller, operator=operator, approved=approved)
    return ()
end


func ERC1155_safe_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256):
    owner_or_approved(_from)
    _safe_transfer_from(_from, to, id, amount)
    return ()
end


func ERC1155_safe_batch_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
    owner_or_approved(_from)
    return _safe_batch_transfer_from(
        _from,
        to,
        ids_len,
        ids,
        amounts_len,
        amounts)
end

#
# Internals
#

func _safe_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256):
    alloc_locals
    # Check args
    assert_not_zero(to)
    uint256_check(id)
    uint256_check(amount)
    # Todo: beforeTokenTransfer

    # Check balance sufficient
    let (local from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # Deduct from sender
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # Add to reciever
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0
    _balances.write(id=id, account=to, value=new_balance)
    let (operator) = get_caller_address()
    TransferSingle.emit(operator,_from,to,id,amount)
    # Todo: doSafeTransferAcceptanceCheck
    return ()
end

func _safe_batch_transfer_from{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*,
        amounts_len : felt, amounts : Uint256*):   
    alloc_locals
    assert_not_zero(to)
    # Check args are equal length arrays
    assert ids_len = amounts_len
    # Recursive call
    safe_batch_transfer_from_iter(
        _from=_from,
        to=to,
        ids_len=ids_len,
        ids=ids,
        amounts_len=amounts_len,
        amounts=amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(operator,_from,to,ids_len,ids,amounts_len,amounts)
    return ()
end

func ERC1155_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256):
    # Cannot mint to zero address
    assert_not_zero(to)
    # Check uints valid
    uint256_check(id)
    uint256_check(amount)
    # beforeTokenTransfer
    # add to minter check for overflow
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0
    _balances.write(id=id, account=to, value=new_balance)
    # doSafeTransferAcceptanceCheck
    let (operator) = get_caller_address()
    TransferSingle.emit(
        operator=operator,
        from_=0,
        to=to,
        id=id,
        value=amount
    )
    return ()
end

func ERC1155_mint_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_len : felt, ids : Uint256*, 
        amounts_len : felt, amounts : Uint256*):
    alloc_locals
    # Cannot mint to zero address
    assert_not_zero(to)
    # Check args are equal length arrays
    assert ids_len = amounts_len
    # Recursive call
    mint_batch_iter(
        to=to,
        ids_len=ids_len,
        ids=ids,
        amounts_len=amounts_len,
        amounts=amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(
        operator=operator,
        from_=0,
        to=to,
        ids_len=ids_len,
        ids=ids,
        values_len=amounts_len,
        values=amounts
    )
    return ()
end

func ERC1155_burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, id : Uint256, amount : Uint256):
    alloc_locals
    assert_not_zero(_from)
    # beforeTokenTransfer
    # Check balance sufficient
    let (local from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # Deduct from burner
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)
    let (operator) = get_caller_address()
    TransferSingle.emit(
        operator=operator,
        from_=_from,
        to=0,
        id=id,
        value=amount
    )
    return ()
end

func ERC1155_burn_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_len : felt, ids : Uint256*,
        amounts_len : felt, amounts : Uint256*):
    alloc_locals
    assert_not_zero(_from)
    # Check args are equal length arrays
    assert ids_len = amounts_len
    # Recursive call
    burn_batch_iter(
        _from=_from,
        ids_len=ids_len,
        ids=ids,
        amounts_len=amounts_len,
        amounts=amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(
        operator=operator,
        from_=_from,
        to=0,
        ids_len=ids_len,
        ids=ids,
        values_len=amounts_len,
        values=amounts
    )
    return ()
end

func _set_approval_for_all{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, operator : felt, approved : felt):
    # check approved is bool
    assert (approved - 0) * (approved - 1) = 0
    # since caller can now be 0
    assert_not_zero(owner*operator)
    assert_not_equal(owner, operator)
    _operator_approvals.write(owner, operator, approved)
    ApprovalForAll.emit(owner,operator,approved)
    return ()
end

func _setURI{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        newuri : felt):
    _uri.write(newuri)
    return()
end

#
# Helpers
#

func balance_of_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*,
        batch_balances_len : felt, batch_balances : Uint256*):  
    if ids_len == 0:
        return ()
    end
    # may be unnecessary now
    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    uint256_check(id)
    let account : felt = [accounts]
    
    let (balance : Uint256) = ERC1155_balance_of(account,id)
    assert [batch_balances] = balance
    return  balance_of_batch_iter(
        accounts_len - 1,
        accounts + 1,
        ids_len - 1,
        ids + Uint256.SIZE,
        batch_balances_len - 1,
        batch_balances + Uint256.SIZE
    )
end

func safe_batch_transfer_from_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
    # Base case
    alloc_locals
    if ids_len == 0:
        return ()
    end

    # Read current entries,  perform Uint256 checks
    let id = [ids]
    uint256_check(id)
    let amount = [amounts]
    uint256_check(amount)

    # Check balance is sufficient
    let (from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # deduct from
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # add to
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0 #overflow protection
    _balances.write(id=id, account=to, value=new_balance)

    # Recursive call
    return safe_batch_transfer_from_iter(
        _from=_from,
        to=to,
        ids_len=ids_len - 1,
        ids=ids + Uint256.SIZE,
        amounts_len=amounts_len - 1,
        amounts=amounts + Uint256.SIZE)
end

func mint_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
    # Base case
    alloc_locals
    if ids_len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    uint256_check(id)
    let amount : Uint256 = [amounts]
    uint256_check(amount)

    # add to
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0 #overflow protection
    _balances.write(id=id, account=to, value=new_balance)

    # Recursive call
    return mint_batch_iter(
        to=to,
        ids_len=ids_len - 1,
        ids=ids + Uint256.SIZE,
        amounts_len=amounts_len - 1,
        amounts=amounts + Uint256.SIZE)
end

func burn_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_len : felt, ids : Uint256*,  amounts_len : felt, amounts : Uint256*):
    # Base case
    alloc_locals
    if ids_len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    uint256_check(id)
    let amount : Uint256 = [amounts]
    uint256_check(amount)

    # Check balance is sufficient
    let (from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # deduct from
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # Recursive call
    return burn_batch_iter(
        _from=_from,
        ids_len=ids_len - 1,
        ids=ids + Uint256.SIZE,
        amounts_len=amounts_len - 1,
        amounts=amounts + Uint256.SIZE)
end

func owner_or_approved{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner):
    let (caller) = get_caller_address()
    if caller == owner:
        return ()
    end
    let (approved) = ERC1155_is_approved_for_all(owner, caller)
    assert approved = 1
    return ()
end