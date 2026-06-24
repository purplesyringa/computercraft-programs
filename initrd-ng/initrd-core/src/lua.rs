use std::{borrow::Cow, collections::HashMap};

pub type LuaString = Cow<'static, [u8]>;
pub type LuaList = Vec<LuaValue>;
pub type LuaTable = HashMap<LuaString, LuaValue>;
pub enum LuaValue {
    Float(f64),
    String(LuaString),
    List(LuaList),
    Table(LuaTable),
}

impl From<f64> for LuaValue {
    fn from(value: f64) -> Self {
        Self::Float(value)
    }
}

impl From<LuaString> for LuaValue {
    fn from(value: LuaString) -> Self {
        Self::String(value)
    }
}

impl From<LuaList> for LuaValue {
    fn from(value: LuaList) -> Self {
        Self::List(value)
    }
}

impl From<LuaTable> for LuaValue {
    fn from(value: LuaTable) -> Self {
        Self::Table(value)
    }
}
