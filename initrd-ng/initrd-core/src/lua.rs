use std::{borrow::Cow, collections::HashMap};

pub type LuaString<'a> = Cow<'a, [u8]>;
pub type LuaList<'a> = Vec<LuaValue<'a>>;
pub type LuaTable<'a> = HashMap<LuaString<'a>, LuaValue<'a>>;
pub enum LuaValue<'a> {
    Float(f64),
    String(LuaString<'a>),
    List(LuaList<'a>),
    Table(LuaTable<'a>),
}

impl<'a> From<f64> for LuaValue<'a> {
    fn from(value: f64) -> Self {
        Self::Float(value)
    }
}

impl<'a> From<LuaString<'a>> for LuaValue<'a> {
    fn from(value: LuaString<'a>) -> Self {
        Self::String(value)
    }
}

impl<'a> From<LuaList<'a>> for LuaValue<'a> {
    fn from(value: LuaList<'a>) -> Self {
        Self::List(value)
    }
}

impl<'a> From<LuaTable<'a>> for LuaValue<'a> {
    fn from(value: LuaTable<'a>) -> Self {
        Self::Table(value)
    }
}
