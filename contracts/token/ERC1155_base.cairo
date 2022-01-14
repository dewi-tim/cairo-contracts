%lang starknet

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)


# Notes: does not implement "data" arguments or do(Batch)SafeTransferAcceptanceCheck until account contracts can be distinguished and hook overriding resolved
const IERC1155_interface_id = 0xd9b67a26
const IERC1155_MetadataURI_interface_id = 0x0e89341c
const IERC165_interface_id = 0x01ffc9a7
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
        accounts_len : felt, accounts : felt*, ids_low_len : felt, ids_low : felt*,
        ids_high_len : felt, ids_high : felt*) -> (
        batch_balances_low_len : felt, batch_balances_low : felt*, batch_balances_high_len : felt,
        batch_balances_high : felt*):
    alloc_locals
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert ids_high_len = accounts_len
    # Allocate memory
    let (local batch_balances_low : felt*) = alloc()
    let (local batch_balances_high : felt*) = alloc()
    let batch_balances_low_len = accounts_len
    let batch_balances_high_len = accounts_len
    # Call iterator
    balance_of_batch_iter(
        accounts_len,
        accounts,
        ids_low_len,
        ids_low,
        ids_high_len,
        ids_high,
        batch_balances_low_len,
        batch_balances_low,
        batch_balances_high_len,
        batch_balances_high)
    let batch_balances_low_len = accounts_len
    let batch_balances_high_len = accounts_len
    return (
        batch_balances_low_len, batch_balances_low, batch_balances_high_len, batch_balances_high)
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
        _from : felt, to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):
    owner_or_approved(_from)
    _safe_batch_transfer_from(
        _from,
        to,
        ids_low_len,
        ids_low,
        ids_high_len,
        ids_high,
        amounts_low_len,
        amounts_low,
        amounts_high_len,
        amounts_high)
    return ()
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
    # Todo: doSafeTransferAcceptanceCheck
    return ()
end

func _safe_batch_transfer_from{
syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):   
    assert_not_zero(to)
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    # Recursive call
    return safe_batch_transfer_from_iter(
        _from=_from,
        to=to,
        ids_low_len=ids_low_len,
        ids_low=ids_low,
        ids_high_len=ids_high_len,
        ids_high=ids_high,
        amounts_low_len=amounts_low_len,
        amounts_low=amounts_low,
        amounts_high_len=amounts_high_len,
        amounts_high=amounts_high)
end

func ERC1155_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256):
    # Cannot mint to zero address
    assert_not_zero(to)
    # beforeTokenTransfer
    # add to minter check for overflow
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0
    _balances.write(id=id, account=to, value=new_balance)
    # doSafeTransferAcceptanceCheck
    return ()
end

func ERC1155_mint_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt, ids_high : felt*,
        amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt, amounts_high : felt*):
    # Cannot mint to zero address
    assert_not_zero(to)
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    # Recursive call
    return mint_batch_iter(
        to=to,
        ids_low_len=ids_low_len,
        ids_low=ids_low,
        ids_high_len=ids_high_len,
        ids_high=ids_high,
        amounts_low_len=amounts_low_len,
        amounts_low=amounts_low,
        amounts_high_len=amounts_high_len,
        amounts_high=amounts_high)
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
    # doSafeTransferAcceptanceCheck
    return ()
end

func ERC1155_burn_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt, ids_high : felt*,
        amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt, amounts_high : felt*):
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    # Recursive call
    return burn_batch_iter(
        _from=_from,
        ids_low_len=ids_low_len,
        ids_low=ids_low,
        ids_high_len=ids_high_len,
        ids_high=ids_high,
        amounts_low_len=amounts_low_len,
        amounts_low=amounts_low,
        amounts_high_len=amounts_high_len,
        amounts_high=amounts_high)
end

func _set_approval_for_all{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, operator : felt, approved : felt):
    # check approved is bool
    assert (approved - 0) * (approved - 1) = 0

    assert_not_equal(owner, operator)
    _operator_approvals.write(owner, operator, approved)
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
        accounts_len : felt, accounts : felt*, ids_low_len : felt, ids_low : felt*,
        ids_high_len : felt, ids_high : felt*, batch_balances_low_len : felt,
        batch_balances_low : felt*, batch_balances_high_len : felt, batch_balances_high : felt*):
    alloc_locals
    if ids_high_len == 0:
        return ()
    end
    let (local __fp__, _) = get_fp_and_pc()
    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    let account : felt = [accounts]
    uint256_check(id)
    let (balance : Uint256) = ERC1155_balance_of(account,id)
    assert [batch_balances_low] = balance.low
    assert [batch_balances_high] = balance.high
   return  balance_of_batch_iter(
        accounts_len - 1,
        accounts + 1,
        ids_low_len - 1,
        ids_low + 1,
        ids_high_len - 1,
        ids_high + 1,
        batch_balances_low_len - 1,
        batch_balances_low + 1,
        batch_balances_high_len - 1,
        batch_balances_high + 1)
end

func safe_batch_transfer_from_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):
    # Base case
    alloc_locals
    if ids_high_len == 0:
        return ()
    end
    let (local __fp__, _) = get_fp_and_pc()

    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
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
        ids_low_len=ids_low_len - 1,
        ids_low=ids_low + 1,
        ids_high_len=ids_high_len - 1,
        ids_high=ids_high + 1,
        amounts_low_len=amounts_low_len - 1,
        amounts_low=amounts_low + 1,
        amounts_high_len=amounts_high_len - 1,
        amounts_high=amounts_high + 1)
end

func mint_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):
    # Base case
    alloc_locals
    if ids_high_len == 0:
        return ()
    end
    let (local __fp__, _) = get_fp_and_pc()

    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
    uint256_check(amount)

    # add to
    let (to_balance : Uint256) = _balances.read(id=id, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0 #overflow protection
    _balances.write(id=id, account=to, value=new_balance)

    # Recursive call
    return mint_batch_iter(
        to=to,
        ids_low_len=ids_low_len - 1,
        ids_low=ids_low + 1,
        ids_high_len=ids_high_len - 1,
        ids_high=ids_high + 1,
        amounts_low_len=amounts_low_len - 1,
        amounts_low=amounts_low + 1,
        amounts_high_len=amounts_high_len - 1,
        amounts_high=amounts_high + 1)
end

func burn_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):
    # Base case
    alloc_locals
    if ids_high_len == 0:
        return ()
    end
    let (local __fp__, _) = get_fp_and_pc()

    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
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
        ids_low_len=ids_low_len - 1,
        ids_low=ids_low + 1,
        ids_high_len=ids_high_len - 1,
        ids_high=ids_high + 1,
        amounts_low_len=amounts_low_len - 1,
        amounts_low=amounts_low + 1,
        amounts_high_len=amounts_high_len - 1,
        amounts_high=amounts_high + 1)
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