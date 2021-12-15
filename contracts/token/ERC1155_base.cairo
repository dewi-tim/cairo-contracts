%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)

#
# Storage
#

@storage_var
func ERC1155_balances(id_low : felt, id_high : felt, account : felt) -> (balance : Uint256):
end

@storage_var
func ERC1155_operator_approvals(account : felt, operator : felt) -> (approved : felt):
end

# TODO: decide URI format
@storage_var
func ERC1155_uri() -> (uri : felt):
end

#
# Constructor
#

func ERC1155_initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        uri : felt):
    ERC1155_uri.write(uri)
    return ()
end

#
# Getters
#

@view
func uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (uri : felt):
    let (uri) = ERC1155_uri.read()
    return (uri)
end

@view
func isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, operator : felt) -> (approved : felt):
    let (approved) = ERC1155_operator_approvals.read(account=account, operator=operator)
    return (approved)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, id : Uint256) -> (balance : Uint256):
    assert_not_zero(account)
    let (balance) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=account)
    return (balance)
end

@view
func balanceOfBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
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

#
# Internals
#

func ERC1155_safe_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256):
    alloc_locals
    # Check args
    assert_not_zero(to)
    uint256_check(id)
    uint256_check(amount)
    # Todo: beforeTokenTransfer

    # Check balance sufficient
    let (local from_balance) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # Deduct from sender
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=_from, value=new_balance)

    # Add to reciever
    # (forall id : sum balances[id] = total supply < uint256_max)
    # => no overflows (as in ERC20)
    let (to_balance : Uint256) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=to)
    let (new_balance : Uint256, _) = uint256_add(to_balance, amount)
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=to, value=new_balance)
    # Todo: doSafeTransferAcceptanceCheck
    return ()
end

func ERC1155_safe_batch_transfer_from{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt,
        ids_high : felt*, amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt,
        amounts_high : felt*):
    # Note: In this form, checks and hooks are repeated unnecessarily
    #       Fix:
    #           1. call helper w/o ERC1155 prefix
    #           2. replace recursion with manual jump-based loops
    #              -- less readable, but more efficient
    alloc_locals
    # Base case
    if ids_high_len == 0:
        return ()
    end
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    let (local __fp__, _) = get_fp_and_pc()
    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
    uint256_check(amount)

    # Check balance is sufficient
    let (from_balance) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # deduct from
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=_from, value=new_balance)

    # add to
    let (to_balance : Uint256) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=to)
    let (new_balance : Uint256, _) = uint256_add(to_balance, amount)  # as above
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=to, value=new_balance)

    # Recursive call
    ERC1155_safe_batch_transfer_from(
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
    return ()
end

func ERC1155_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256):
    assert_not_zero(to)
    # beforeTokenTransfer
    # add to minter check for overflow
    let (to_balance : Uint256) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=to, value=new_balance)
    # doSafeTransferAcceptanceCheck
    return ()
end

func ERC1155_mint_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt, ids_high : felt*,
        amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt, amounts_high : felt*):
    # Note: In this form, checks and hooks are repeated unnecessarily
    #       Fix:
    #           1. call helper w/o ERC1155 prefix
    #           2. replace recursion with manual jump-based loops
    #              -- less readable, but more efficient
    alloc_locals
    # Base case
    if ids_high_len == 0:
        return ()
    end
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    let (local __fp__, _) = get_fp_and_pc()
    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
    uint256_check(amount)

    # add to minter
    let (to_balance : Uint256) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=to)
    let (new_balance : Uint256, carry) = uint256_add(to_balance, amount)
    assert carry = 0
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=to, value=new_balance)

    # Recursive call
    ERC1155_mint_batch(
        to=to,
        ids_low_len=ids_low_len - 1,
        ids_low=ids_low + 1,
        ids_high_len=ids_high_len - 1,
        ids_high=ids_high + 1,
        amounts_low_len=amounts_low_len - 1,
        amounts_low=amounts_low + 1,
        amounts_high_len=amounts_high_len - 1,
        amounts_high=amounts_high + 1)
    return ()
end

func ERC1155_burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, id : Uint256, amount : Uint256):
    alloc_locals
    assert_not_zero(_from)
    # beforeTokenTransfer
    # Check balance sufficient
    let (local from_balance) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # Deduct from burner
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=_from, value=new_balance)
    # doSafeTransferAcceptanceCheck
    return ()
end

func ERC1155_burn_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_low_len : felt, ids_low : felt*, ids_high_len : felt, ids_high : felt*,
        amounts_low_len : felt, amounts_low : felt*, amounts_high_len : felt, amounts_high : felt*):
    # Note: In this form, checks and hooks are repeated unnecessarily
    #       Fix:
    #           1. call helper w/o ERC1155 prefix
    #           2. replace recursion with manual jump-based loops
    #              -- less readable, but more efficient
    alloc_locals
    # Base case
    if ids_high_len == 0:
        return ()
    end
    # Check args are equal length arrays
    assert ids_high_len = ids_low_len
    assert amounts_high_len = amounts_low_len
    assert ids_high_len = amounts_high_len
    let (local __fp__, _) = get_fp_and_pc()
    # Read current entries, Todo: perform Uint256 checks
    local id : Uint256 = Uint256([ids_low], [ids_high])
    uint256_check(id)
    local amount : Uint256 = Uint256([amounts_low], [amounts_high])
    uint256_check(amount)

    # Check balance sufficient
    let (local from_balance) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=_from)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    assert_not_zero(sufficient_balance)

    # Deduct from burner
    let (new_balance : Uint256) = uint256_sub(from_balance, amount)
    ERC1155_balances.write(id_low=id.low, id_high=id.high, account=_from, value=new_balance)

    # Recursive call
    ERC1155_burn_batch(
        _from,
        ids_low_len=ids_low_len - 1,
        ids_low=ids_low + 1,
        ids_high_len=ids_high_len - 1,
        ids_high=ids_high + 1,
        amounts_low_len=amounts_low_len - 1,
        amounts_low=amounts_low + 1,
        amounts_high_len=amounts_high_len - 1,
        amounts_high=amounts_high + 1)
    return ()
end

func ERC1155_set_approval_for_all{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, operator : felt, approved : felt):
    # check approved is bool
    assert (approved - 0) * (approved - 1) = 0

    assert_not_equal(owner, operator)
    ERC1155_operator_approvals.write(owner, operator, approved)
    return ()
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
    let (balance : Uint256) = ERC1155_balances.read(id_low=id.low, id_high=id.high, account=account)
    assert [batch_balances_low] = balance.low
    assert [batch_balances_high] = balance.high
    balance_of_batch_iter(
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
    return ()
end