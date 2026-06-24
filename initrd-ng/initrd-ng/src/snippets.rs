use crate::huffman::Node;
use initrd_core::prelude::*;

#[expect(clippy::boxed_local, reason = "Box<Node> is a recursive type")]
fn to_lua_tree(node: Box<Node>) -> LuaValue {
    match *node {
        Node::Leaf(v) => LuaValue::Float(v as f64),
        Node::Branch(l, r) => LuaValue::List(vec![to_lua_tree(l), to_lua_tree(r)]),
    }
}

pub fn generate_sfx(data: &[u8], tree: Box<Node>, total_bit_len: usize, shift: usize) -> Vec<u8> {
    let data = LuaString::from(data.to_owned()).into();
    let tree = to_lua_tree(tree);
    let limit = (8 + total_bit_len).to_string();
    let shift = (shift + 1).to_string();
    initrd_core::templates::substitute_template(
        include_bytes!(concat!(env!("OUT_DIR"), "/decompress-template.lua")),
        [
            ("__DATA__", &serialize_to_vec(&data)[..]),
            ("__TREE__", &serialize_to_vec(&tree)[..]),
            ("__LIMIT__", limit.as_bytes()),
            ("__SHIFT__", shift.as_bytes()),
        ]
        .into(),
    )
}
