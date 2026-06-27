use crate::lua::*;
use regex::bytes::Regex;
use std::{borrow::Cow, io::Write, sync::LazyLock};

fn serialize_key(out: &mut Vec<u8>, k: &LuaString) {
    if !k.is_empty()
        && k.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_')
        && !k[0].is_ascii_digit()
        && !matches!(
            &k[..],
            b"and"
                | b"break"
                | b"do"
                | b"else"
                | b"elseif"
                | b"end"
                | b"false"
                | b"for"
                | b"function"
                | b"global"
                | b"goto"
                | b"if"
                | b"in"
                | b"local"
                | b"nil"
                | b"not"
                | b"or"
                | b"repeat"
                | b"return"
                | b"then"
                | b"true"
                | b"until"
                | b"while"
        )
    {
        out.extend(k.iter());
    } else {
        out.push(b'[');
        serialize_string(out, k, true);
        out.push(b']');
    }
}

static RAW_STRING_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\[\]]=*").unwrap());

fn find_level(s: &[u8]) -> usize {
    RAW_STRING_REGEX
        .find_iter(s)
        .filter(|m| s.get(m.end()) == Some(&s[m.start()]))
        .map(|m| m.len())
        .max()
        .unwrap_or(0)
}

fn serialize_string(out: &mut Vec<u8>, s: &LuaString, in_key: bool) {
    if !s.iter().any(|&c| c == b'\\' || c == b'\n' || c == b'\r') {
        let quote = if !s.contains(&b'"') {
            Some(b'"')
        } else if !s.contains(&b'\'') {
            Some(b'\'')
        } else {
            None
        };
        if let Some(quote) = quote {
            out.push(quote);
            out.extend(s.iter());
            out.push(quote);
            return;
        }
    }

    // Lua strips away CR characters, so we escape them manually
    let mut prefix = vec![];
    let mut suffix = vec![];
    let s: Cow<'_, [u8]> = if !s.contains(&b'\r') {
        if in_key {
            // Prevent [[[text]]] for [[text]] in [key] context by adding a space,
            // so that it is serialized as [ [[key]]] instead
            prefix.push(b' ');
        }
        Cow::Borrowed(s)
    } else {
        let mut counts = [0usize; 256];
        for &c in s.iter() {
            counts[c as usize] += 1;
        }
        for &c in b"^$()%.[]*+-?'\r\\".iter() {
            counts[c as usize] = usize::MAX;
        }
        let escape = (0..=u8::MAX).min_by_key(|&c| counts[c as usize]).unwrap();
        if counts[escape as usize] == 0 {
            prefix.push(b'(');
            suffix.extend(b"):gsub('");
            suffix.push(escape);
            suffix.extend(br"','\r')");
            s.iter()
                .map(|&c| if c == b'\r' { escape } else { c })
                .collect()
        } else {
            prefix.push(b'(');
            suffix.extend(b"):gsub('");
            suffix.push(escape);
            suffix.extend(br"r','\r'):gsub('");
            suffix.push(escape);
            suffix.extend(b"]','");
            suffix.push(escape);
            suffix.extend(b"')");
            let mut inner = vec![];
            for &c in s.iter() {
                if c == b'\r' {
                    inner.extend([escape, b'r']);
                } else if c == escape {
                    inner.extend([escape, b']']);
                } else {
                    inner.push(c);
                }
            }
            inner.into()
        }
    };

    // Somewhat surprisingly, Lua forbids even opening brackets inside brackets.
    let level = find_level(&s);

    out.extend(prefix);
    out.push(b'[');
    out.extend((0..level).map(|_| b'='));
    out.push(b'[');
    if let Some(b'\n') = s.first() {
        out.push(b'\n');
    }
    out.extend(s.iter());
    out.push(b']');
    out.extend((0..level).map(|_| b'='));
    out.push(b']');
    out.extend(suffix);
}

fn serialize_list(out: &mut Vec<u8>, t: &LuaList) {
    out.push(b'{');
    let mut is_first = true;
    for v in t.iter() {
        if is_first {
            is_first = false;
        } else {
            out.push(b',');
        }
        serialize(out, v);
    }
    out.push(b'}');
}

fn serialize_table(out: &mut Vec<u8>, t: &LuaTable) {
    out.push(b'{');
    let mut is_first = true;
    let mut sorted_kv = t.iter().collect::<Vec<_>>();
    sorted_kv.sort_by_key(|(k, _)| *k);
    for (k, v) in sorted_kv {
        if is_first {
            is_first = false;
        } else {
            out.push(b',');
        }
        serialize_key(out, k);
        out.push(b'=');
        serialize(out, v);
    }
    out.push(b'}');
}

pub fn serialize(out: &mut Vec<u8>, v: &LuaValue) {
    match v {
        LuaValue::Float(f) => write!(out, "{f}").unwrap(),
        LuaValue::String(b) => serialize_string(out, b, false),
        LuaValue::List(t) => serialize_list(out, t),
        LuaValue::Table(t) => serialize_table(out, t),
    }
}

pub fn serialize_to_vec(v: &LuaValue) -> Vec<u8> {
    let mut out = vec![];
    serialize(&mut out, v);
    out
}
