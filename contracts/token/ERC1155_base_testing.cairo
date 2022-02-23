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
    with_attr error_message("ERC1155: balance query for the zero address"):
        assert_not_zero(account)
    end
    let (balance) = _balances.read(id=id, account=account)
    return (balance)
end


func ERC1155_balance_of_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*) -> (
        batch_balances_len : felt, batch_balances : Uint256*):
    alloc_locals
    # Check args are equal length arrays
    with_attr error_message("ERC1155: accounts and ids length mismatch"):
        assert ids_len = accounts_len
    end 
    # Allocate memory
    let (local batch_balances : Uint256*) = alloc()
    let len = accounts_len
    # Call iterator
    balance_of_batch_iter(
        len,
        accounts,
        ids,
        batch_balances)
    return (
        batch_balances_len=len, batch_balances=batch_balances)
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
    # Non-zero caller asserted in called function
    _set_approval_for_all(owner=caller, operator=operator, approved=approved)
    return ()
end


func ERC1155_safe_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256):
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    with_attr error_message("ERC1155: caller is not owner nor approved"):
        owner_or_approved(_from)
    end
    _safe_transfer_from(_from, to, id, amount)
    return ()
end


func ERC1155_safe_batch_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
    with_attr error_message("ERC1155: transfer caller is not owner nor approved"):
        owner_or_approved(_from)
    end
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
    with_attr error_message("ERC1155: transfer to the zero address"):
        assert_not_zero(to)
    end
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
        uint256_check(amount)
    end
    # Todo: beforeTokenTransfer

    # Check balance sufficient
    let (local from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: insufficient balance for transfer"):
        assert_not_zero(sufficient_balance)
    end
    # Deduct from sender
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # Add to reciever
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    with_attr error_message("arithmetic overflow"):
        assert carry = 0
    end
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
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert_not_zero(to)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: transfer to the zero address"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    safe_batch_transfer_from_iter(
        _from,
        to,
        len,
        ids,
        amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(operator,_from,to,ids_len,ids,amounts_len,amounts)
    return ()
end

func ERC1155_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256):
    
    # Cannot mint to zero address
    with_attr error_message("ERC1155: mint to the zero address"):
        assert_not_zero(to)
    end
    # Check uints valid
    with_attr error_message("ERC1155: invalid uint256 in calldata"):
        uint256_check(id)
        uint256_check(amount)
    end
    # beforeTokenTransfer
    # add to minter check for overflow
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    with_attr error_message("ERC1155: arithmetic overflow"):
        assert carry = 0
    end
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
    with_attr error_message("ERC1155: mint to the zero address"):
        assert_not_zero(to)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    mint_batch_iter(
        to,
        len,
        ids,
        amounts)
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
    with_attr error_message("ERC1155: burn from the zero address"):
        assert_not_zero(_from)
    end
    # beforeTokenTransfer
    # Check balance sufficient
    let (local from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: burn amount exceeds balance"):
        assert_not_zero(sufficient_balance)
    end
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
    with_attr error_message("ERC1155: burn from the zero address"):
        assert_not_zero(_from)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    burn_batch_iter(
        _from,
        len,
        ids,
        amounts)
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
        len : felt, accounts : felt*, ids : Uint256*, batch_balances : Uint256*):  
    if len == 0:
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
        len - 1,
        accounts + 1,
        ids + Uint256.SIZE,
        batch_balances + Uint256.SIZE
    )
end

func safe_batch_transfer_from_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, len : felt, ids : Uint256*, amounts : Uint256*):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries,  perform Uint256 checks
    let id = [ids]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
    end
    let amount = [amounts]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(amount)
    end

    # Check balance is sufficient
    let (from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: insufficient balance for transfer"):
        assert_not_zero(sufficient_balance)
    end
    # deduct from
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # add to
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    with_attr error_message("arithmetic overflow"):
        assert carry = 0 #overflow protection
    end
    _balances.write(id=id, account=to, value=new_balance)

    # Recursive call
    return safe_batch_transfer_from_iter(
        _from,
        to,
        len - 1,
        ids + Uint256.SIZE,
        amounts + Uint256.SIZE)
end

func mint_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, len : felt, ids : Uint256*, amounts : Uint256*):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    let amount : Uint256 = [amounts]
    with_attr error_message("ERC1155: invalid uint256 in calldata"):
        uint256_check(id)  
        uint256_check(amount)
    end
    # add to
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    with_attr error_message("ERC1155: arithmetic overflow"):
        assert carry = 0 #overflow protection
    end
    _balances.write(id=id, account=to, value=new_balance)

    # Recursive call
    return mint_batch_iter(
        to,
        len - 1,
        ids + Uint256.SIZE,
        amounts + Uint256.SIZE)
end

func burn_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, len : felt, ids : Uint256*, amounts : Uint256*):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
    end
    let amount : Uint256 = [amounts]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(amount)
    end

    # Check balance is sufficient
    let (from_balance) = _balances.read(id=id, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: burn amount exceeds balance"):
        assert_not_zero(sufficient_balance)
    end

    # deduct from
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    _balances.write(id=id, account=_from, value=new_balance)

    # Recursive call
    return burn_batch_iter(
        _from,
        len - 1,
        ids + Uint256.SIZE,
        amounts + Uint256.SIZE)
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