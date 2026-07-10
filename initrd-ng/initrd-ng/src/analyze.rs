use crate::fs;
use cursive::{
    Cursive, CursiveExt, View,
    align::HAlign,
    event::Key,
    style::BorderStyle,
    theme::Theme,
    view::Resizable,
    views::{
        Button, DummyView, LinearLayout, OnEventView, Panel, ProgressBar, ScrollView, TextView,
    },
};
use rayon::prelude::*;
use std::{
    cmp::Reverse,
    collections::hash_map::HashMap,
    path::{Path, PathBuf},
    sync::mpsc,
};

// XXX: Replace with `std::sync::oneshot` when it is stable
use std::sync::mpsc as oneshot;

fn initrd_size(tree: &fs::Entry, ignore: Option<&Path>) -> isize {
    fs::make_initrd(tree, false, ignore).len().cast_signed()
}

fn process_dir(total: isize, tree: &fs::Entry, dir: &Path) -> (isize, Vec<(isize, String, bool)>) {
    let names = tree
        .walk_to(dir)
        .expect("no such directory")
        .iter()
        .map(|(name, entry)| (Some(dir.join(name)), name.clone(), entry.is_dir()))
        .collect::<Vec<_>>();

    let (cur_total, mut sizes) = rayon::join(
        || total - initrd_size(tree, Some(dir)),
        || {
            names
                .into_par_iter()
                .map(|(ignore, name, is_dir)| {
                    (total - initrd_size(tree, ignore.as_deref()), name, is_dir)
                })
                .collect::<Vec<_>>()
        },
    );
    sizes.sort_by(|(i1, n1, _), (i2, n2, _)| (Reverse(i1), n1).cmp(&(Reverse(i2), n2)));
    (cur_total, sizes)
}

fn fractional_percent(value: usize, (min, max): (usize, usize)) -> String {
    let percent = 100. * (value - min) as f64 / (max - min) as f64;
    format!("{percent:.1}%")
}

fn impact_view(max: isize, current: isize) -> impl View {
    let mut progress = ProgressBar::new()
        .max(max.max(0) as usize)
        .with_label(fractional_percent);
    progress.set_value(current.max(0) as usize);
    progress.fixed_width(12)
}

fn dismissable_view(view: impl View, has_dismiss: bool, title: String) -> impl View {
    let dialog = Panel::new(view).title(title).title_position(HAlign::Left);
    let mut view = OnEventView::new(dialog);
    if has_dismiss {
        view.set_on_event(Key::Esc, |siv| {
            siv.pop_layer();
        });
    }
    view
}

fn impacts_view(
    dir: PathBuf,
    tx: &mpsc::Sender<(PathBuf, oneshot::Sender<Box<dyn View>>)>,
    total: isize,
    this_total: isize,
    impacts: &[(isize, String, bool)],
) -> impl View {
    let mut layout = LinearLayout::vertical();

    for (impact, name, is_dir) in impacts {
        let mut inner = LinearLayout::horizontal();

        inner.add_child(
            TextView::new(format!("{impact}"))
                .h_align(HAlign::Right)
                .fixed_width(8),
        );
        inner.add_child(DummyView.fixed_width(1));

        inner.add_child(impact_view(total, *impact));
        inner.add_child(DummyView.fixed_width(1));

        inner.add_child(impact_view(this_total, *impact));
        inner.add_child(DummyView.fixed_width(1));

        if *is_dir {
            let tx = tx.clone();
            let new_dir = dir.join(name);
            inner.add_child(Button::new(name, move |siv| {
                let (otx, orx) = oneshot::channel();
                tx.send((new_dir.clone(), otx)).unwrap();
                siv.add_fullscreen_layer(orx.recv().unwrap());
            }));
        } else {
            inner.add_child(TextView::new(name));
        }

        layout.add_child(inner);
    }

    dismissable_view(
        ScrollView::new(layout),
        dir.parent().is_some(),
        format!("{} ({this_total}/{total})", dir.into_string().unwrap()),
    )
    .full_screen()
}

pub fn analyze(sysroot: &Path) {
    let tree = fs::build_tree(sysroot).unwrap();
    let total = initrd_size(&tree, None);

    let mut siv = Cursive::new();

    siv.set_theme(Theme {
        shadow: true,
        borders: BorderStyle::Simple,
        palette: {
            use cursive::style::{BaseColor::*, Color, Palette, PaletteColor::*};
            let mut p = Palette::default();

            p[Background] = Color::TerminalDefault;
            p[View] = Color::TerminalDefault;

            p[Primary] = Color::TerminalDefault;
            p[Secondary] = Blue.light();
            p[Tertiary] = Black.light();

            p[TitlePrimary] = Yellow.dark();
            p[TitleSecondary] = Yellow.dark();

            p[Highlight] = Yellow.dark();
            p[HighlightInactive] = White.dark();
            p[HighlightText] = Black.dark();

            p
        },
    });

    let (tx, rx) = mpsc::channel::<(PathBuf, _)>();

    let new_tx = tx.clone();
    rayon::spawn(move || {
        let mut cache = HashMap::new();
        for (dir, otx) in rx {
            let (cur_impact, impacts) = cache
                .entry(dir.clone())
                .or_insert_with(|| process_dir(total, &tree, &dir));
            let view = impacts_view(dir, &new_tx, total, *cur_impact, impacts);
            otx.send(Box::new(view)).unwrap();
        }
    });

    let (otx, orx) = oneshot::channel();
    tx.send(("/".into(), otx)).unwrap();
    siv.add_fullscreen_layer(orx.recv().unwrap());

    siv.add_global_callback('q', |s| s.quit());

    siv.run();
}
