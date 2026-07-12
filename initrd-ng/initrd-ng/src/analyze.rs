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
};

fn initrd_size(tree: &fs::Entry, ignore: Option<&Path>) -> isize {
    fs::make_initrd(tree, false, ignore).len().cast_signed()
}

struct Analyzer {
    tree: fs::Entry,
    total: isize,
}

struct AnalyzedDirectory {
    this_total: isize,
    impacts: Vec<(isize, String, bool)>,
}

impl Analyzer {
    fn new(sysroot: &Path) -> Self {
        let tree = fs::build_tree(sysroot).unwrap();
        let total = initrd_size(&tree, None);
        Self { tree, total }
    }

    fn impact(&self, dir: &Path) -> isize {
        self.total - initrd_size(&self.tree, Some(dir))
    }

    fn analyze(&self, dir: &Path) -> AnalyzedDirectory {
        let names = self
            .tree
            .walk_to(dir)
            .expect("no such directory")
            .iter()
            .map(|(name, entry)| (dir.join(name), name.clone(), entry.is_dir()))
            .collect::<Vec<_>>();

        let (this_total, mut impacts) = rayon::join(
            || self.impact(dir),
            || {
                names
                    .into_par_iter()
                    .map(|(path, name, is_dir)| (self.impact(&path), name, is_dir))
                    .collect::<Vec<_>>()
            },
        );
        impacts.sort_by(|(i1, n1, _), (i2, n2, _)| (Reverse(i1), n1).cmp(&(Reverse(i2), n2)));

        AnalyzedDirectory {
            this_total,
            impacts,
        }
    }
}

struct Controller {
    analyzer: Analyzer,
    cache: HashMap<PathBuf, AnalyzedDirectory>,
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

impl Controller {
    fn new(sysroot: &Path) -> Self {
        Self {
            analyzer: Analyzer::new(sysroot),
            cache: HashMap::new(),
        }
    }

    fn impacts_view(&mut self, dir: impl AsRef<Path>) -> impl View {
        let dir = dir.as_ref();

        let res = self
            .cache
            .entry(dir.into())
            .or_insert_with(|| self.analyzer.analyze(dir));

        let mut layout = LinearLayout::vertical();

        for (impact, name, is_dir) in &res.impacts {
            let mut inner = LinearLayout::horizontal();

            inner.add_child(
                TextView::new(format!("{impact}"))
                    .h_align(HAlign::Right)
                    .fixed_width(8),
            );
            inner.add_child(DummyView.fixed_width(1));

            inner.add_child(impact_view(self.analyzer.total, *impact));
            inner.add_child(DummyView.fixed_width(1));

            inner.add_child(impact_view(res.this_total, *impact));
            inner.add_child(DummyView.fixed_width(1));

            if *is_dir {
                let new_dir = dir.join(name);
                inner.add_child(Button::new(name, move |siv| {
                    let layer = siv
                        .user_data::<Controller>()
                        .unwrap()
                        .impacts_view(&new_dir);
                    siv.add_fullscreen_layer(layer);
                }));
            } else {
                inner.add_child(TextView::new(name));
            }

            layout.add_child(inner);
        }

        dismissable_view(
            ScrollView::new(layout),
            dir.parent().is_some(),
            format!(
                "{} ({}/{})",
                dir.to_str().unwrap(),
                res.this_total,
                self.analyzer.total
            ),
        )
        .full_screen()
    }
}

pub fn analyze(sysroot: &Path) {
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

    siv.set_user_data(Controller::new(sysroot));

    let layer = siv.user_data::<Controller>().unwrap().impacts_view("/");
    siv.add_fullscreen_layer(layer);

    siv.add_global_callback('q', |s| s.quit());

    siv.run();
}
