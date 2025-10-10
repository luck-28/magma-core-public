module magma_clmm::acl;

use move_stl::linked_table::{Self, LinkedTable};

const ErrInvalidRole: u64 = 1;

public struct ACL has store {
    permissions: LinkedTable<address, u128>,
}

public struct Member has copy, drop, store {
    address: address,
    permission: u128,
}

public fun new(ctx: &mut TxContext) : ACL {
    ACL {
        permissions: linked_table::new<address, u128>(ctx)
    }
}

public fun add_role(acl: &mut ACL, member: address, role: u8) {
    assert!(role < 128, ErrInvalidRole);
    if (acl.permissions.contains(member)) {
        let roles = acl.permissions.borrow_mut(member);
        *roles = *roles | 1 << role;
    } else {
        acl.permissions.push_back(member, 1 << role);
    };
}

public fun get_members(acl: &ACL) : vector<Member> {
    let mut ret = vector::empty();
    let mut maybe_key = acl.permissions.head();
    while (maybe_key.is_some()) {
        let addr = *maybe_key.borrow();
        let permission_node = acl.permissions.borrow_node(addr);
        ret.push_back(Member{
            address: addr,
            permission: *permission_node.borrow_value(),
        });
        maybe_key = permission_node.next();
    };
    ret
}

public fun get_permission(acl: &ACL, member: address) : u128 {
    if (!acl.permissions.contains(member)) {
        0
    } else {
        *acl.permissions.borrow(member)
    }
}

public fun has_role(acl: &ACL, member: address, role: u8) : bool {
    assert!(role < 128, ErrInvalidRole);
    acl.permissions.contains(member) && *acl.permissions.borrow(member) & 1 << role > 0
}

public fun remove_member(acl: &mut ACL, member: address) {
    if (acl.permissions.contains(member)) {
        acl.permissions.remove(member);
    };
}

public fun remove_role(acl: &mut ACL, member: address, role: u8) {
    assert!(role < 128, ErrInvalidRole);
    if (acl.permissions.contains(member)) {
        let permission = acl.permissions.borrow_mut(member);
        if (*permission & 1 << role > 0) {
            *permission = *permission - (1 << role);
        }
    };
}

public fun set_roles(acl: &mut ACL, member: address, roles: u128) {
    if (acl.permissions.contains(member)) {
        *acl.permissions.borrow_mut(member) = roles;
    } else {
        acl.permissions.push_back(member, roles);
    };
}
