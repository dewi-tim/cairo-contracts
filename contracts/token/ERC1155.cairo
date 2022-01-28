%lang starknet
%builtins pedersen range_check

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)

from contracts.token.ERC1155_base import (
    ERC1155_initializer, ERC1155_balance_of, ERC1155_balance_of_batch,
    ERC1155_is_approved_for_all, ERC1155_uri, ERC1155_safe_transfer_from,
    ERC1155_safe_batch_transfer_from, ERC1155_mint, ERC1155_mint_batch, ERC1155_burn,
    ERC1155_burn_batch, ERC1155_set_approval_for_all, ERC1155_supports_interface)

# note: data args do nothing, for compatibility only

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(uri : felt):
    ERC1155_initializer(uri)
    return ()
end

#
# Views
#

@view
func supportsInterface(interface_id) -> (res : felt):
    return ERC1155_supports_interface(interface_id)
end

@view
func uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (uri : felt):
    return ERC1155_uri()
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, id : Uint256) -> (balance : Uint256):
    return ERC1155_balance_of(account,id)
end

@view
func balanceOfBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*) -> (
        batch_balances_len : felt, batch_balances : Uint256*):
    return ERC1155_balance_of_batch(
        accounts_len,
        accounts,
        ids_len,
        ids
    )
end

@view
func isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, operator : felt) -> (approved : felt):
    return ERC1155_is_approved_for_all(account,operator)
end


#
# Externals
#

@external
func setApprovalForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        operator : felt, approved : felt):
    return ERC1155_set_approval_for_all(operator=operator, approved=approved)
end

@external
func safeTransferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256,
        data_len : felt, data : felt*):
    return ERC1155_safe_transfer_from(_from, to, id, amount)
end

@external
func safeBatchTransferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*, 
        amounts_len : felt, amounts : Uint256*, data_len : felt, data : felt*):
    return ERC1155_safe_batch_transfer_from(
        _from,
        to,
        ids_len,
        ids,
        amounts_len,
        amounts)
end

#
# Testing only 
#

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*):
    return ERC1155_mint(to, id, amount)
end

@external
func mint_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_len : felt, ids : Uint256*, 
        amounts_len : felt, amounts : Uint256*, 
        data_len : felt, data : felt*): 
    return ERC1155_mint_batch(
        to,
        ids_len,
        ids,
        amounts_len,
        amounts)
end

@external
func burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, id : Uint256, amount : Uint256):
    return ERC1155_burn(_from, id, amount)
end

@external
func burn_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, ids_len : felt, ids : Uint256*, 
        amounts_len : felt, amounts : Uint256*):
    return ERC1155_burn_batch(
        _from,
        ids_len,
        ids,
        amounts_len,
        amounts)
end

