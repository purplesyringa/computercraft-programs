use lazy_regex::regex::bytes::Captures;
use std::collections::HashMap;

pub fn substitute_template(template: &[u8], subst: HashMap<&str, &[u8]>) -> Vec<u8> {
    lazy_regex::bytes_regex!("__[A-Z0-9_]+__")
        .replace_all(template, |captures: &Captures<'_>| {
            let capture = &template[captures.get(0).unwrap().range()];
            // We can't use `subst[capture]`, as regex matches all __WORDS__,
            // even if some of them are to be substituted in a later call here.
            subst
                .get(str::from_utf8(capture).unwrap())
                .copied()
                .unwrap_or(capture)
        })
        .into()
}
