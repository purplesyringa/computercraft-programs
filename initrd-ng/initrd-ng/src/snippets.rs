use initrd_core::prelude::*;

pub fn generate_sfx(
    data: &[u8],
    src_cache: &[u8],
    tables: Vec<u8>,
    limit: usize,
    shift: usize,
) -> Vec<u8> {
    let data = LuaString::from(data.to_owned()).into();
    let src_cache = LuaString::from(src_cache).into();
    let tables = LuaString::from(tables).into();
    let limit = (limit + 1).to_string();
    let shift = (shift + 1).to_string();
    initrd_core::templates::substitute_template(
        include_bytes!(concat!(env!("OUT_DIR"), "/decompress-template.lua")),
        [
            ("__DATA__", &serialize_to_vec(&data)[..]),
            ("__CACHE__", &serialize_to_vec(&src_cache)[..]),
            ("__TABLES__", &serialize_to_vec(&tables)[..]),
            ("__LIMIT__", limit.as_bytes()),
            ("__SHIFT__", shift.as_bytes()),
        ]
        .into(),
    )
}
