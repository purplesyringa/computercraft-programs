use crate::lua::*;
use std::{borrow::Cow, collections::BTreeSet, io::Write};

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

fn find_level(s: &[u8]) -> usize {
    let banned_levels = lazy_regex::bytes_regex!(r"[\[\]]=*")
        .find_iter(s)
        .filter(|m| s.get(m.end()) == Some(&s[m.start()]))
        .map(|m| m.len() - 1)
        .collect::<BTreeSet<_>>();
    (0..).find(|level| !banned_levels.contains(level)).unwrap()
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
        prefix.push(b'(');
        if counts[escape as usize] == 0 {
            suffix.extend(b"):gsub('");
            suffix.push(escape);
            suffix.extend(br"','\r')");
        } else {
            suffix.extend(b"):gsub('");
            suffix.push(escape);
            suffix.extend(b"',(function(i)return function()i=i+1 return bit32.btest(('");

            (s.iter().filter(|&&c| c == b'\r' || c == escape))
                .zip(core::iter::repeat(0..7).flatten())
                .for_each(|(&c, bit)| {
                    if bit == 0 {
                        suffix.push(0x80);
                    }
                    if c == b'\r' {
                        *suffix.last_mut().unwrap() |= 1 << bit;
                    }
                });

            suffix.extend(br"'):byte(math.floor(i/7)),2^(i%7))and'\r'end end)(6))");
        }
        s.iter()
            .map(|&c| if c == b'\r' { escape } else { c })
            .collect()
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
