%lang starknet
%builtins pedersen range_check

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check
)

from contracts.token.ERC1155_base import (
    ERC1155_initializer,
    ERC1155_balances,
    ERC1155_operator_approvals,
    ERC1155_safe_transfer_from,
    ERC1155_safe_batch_transfer_from,
    ERC1155_mint,
    ERC1155_mint_batch,
    ERC1155_burn,
    ERC1155_burn_batch,
    ERC1155_set_approval_for_all
)

#
# Constructor
#

@constructor
func constructor{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        uri : felt
    ):
    ERC1155_initializer(uri)
    return ()
end

#
# Externals
#

@external
func setApprovalForAll{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(
        operator : felt,
        approved : felt
    ):
    let (caller) = get_caller_address()
    ERC1155_set_approval_for_all(
        owner=caller,
        operator=operator,
        approved=approved
    )
    return ()
end

@external 
func safeTransferFrom{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(
        _from : felt,
        to : felt,
        id : Uint256,
        amount : Uint256
    ):
    is_owner_or_approved(_from)
    ERC1155_safe_transfer_from(_from,to,id,amount)
    return()
end

@external 
func safeBatchTransferFrom{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(
        _from : felt,
        to : felt,
        ids_low_len : felt,
        ids_low : felt*,
        ids_high_len : felt,
        ids_high : felt*,
        amounts_low_len : felt,
        amounts_low : felt*,
        amounts_high_len : felt,
        amounts_high : felt*,
    ):
    is_owner_or_approved(_from)
    ERC1155_safe_batch_transfer_from(
        _from,
        to,
        ids_low_len,
        ids_low,
        ids_high_len,
        ids_high,
        amounts_low_len,
        amounts_low,
        amounts_high_len,
        amounts_high,
    )
    return()
end

#
# Testing
#

@external
func mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(to : felt, id : Uint256, amount : Uint256):
    ERC1155_mint(to,id,amount)
    return ()
end

@external
func mint_batch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(
        to : felt,
        ids_low_len : felt,
        ids_low : felt*,
        ids_high_len : felt,
        ids_high : felt*,    
        amounts_low_len : felt,
        amounts_low : felt*,
        amounts_high_len : felt,
        amounts_high : felt*
    ):
    ERC1155_mint_batch(
        to,
        ids_low_len,
        ids_low,
        ids_high_len,
        ids_high,
        amounts_low_len,
        amounts_low,
        amounts_high_len,
        amounts_high
    )
    return ()
end

@external
func burn{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(_from : felt, id : Uint256, amount : Uint256):
    ERC1155_burn(_from,id,amount)
    return ()
end

@external
func burn_batch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(
        _from : felt,
        ids_low_len : felt,
        ids_low : felt*,
        ids_high_len : felt,
        ids_high : felt*,    
        amounts_low_len : felt,
        amounts_low : felt*,
        amounts_high_len : felt,
        amounts_high : felt*
    ):
    ERC1155_burn_batch(
        _from,
        ids_low_len,
        ids_low,
        ids_high_len,
        ids_high,
        amounts_low_len,
        amounts_low,
        amounts_high_len,
        amounts_high
    )
    return ()
end

#
# Helpers
#

func is_owner_or_approved{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(owner):
    alloc_locals
    let (local caller) = get_caller_address()
    if caller == owner:
        tempvar is_caller = 1
    else:
        tempvar is_caller = 0
    end
    let (approved) = ERC1155_operator_approvals.read(owner,caller)
    assert (1-approved)*(1-is_caller) = 0
    return ()
end









    
    