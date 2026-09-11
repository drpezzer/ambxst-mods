# Custom GTK CSS

Keeps your own GTK CSS alive across Ambxst's theme regeneration.

Ambxst writes `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` from
scratch every time the palette changes (wallpaper change, theme edit, shell
update, light/dark flip). The file is a plain `echo | tee`, so any rule you add
to it by hand is gone at the next regeneration. This mod makes the generated
file end with

```css
@import url("custom.css");
```

whenever a `custom.css` exists in the same directory. Put your overrides in
`~/.config/gtk-3.0/custom.css` (and/or `~/.config/gtk-4.0/custom.css`); the
shell never touches those files.

## What it changes

One file, two insertions: `modules/theme/GtkGenerator.qml` gets a constant and
one extra line in the shell command that writes the CSS. The import is only
added when the file exists, so GTK never logs a missing-import warning and a
setup without a `custom.css` behaves exactly like stock.

## Usage

1. Enable the mod and reload the shell (`ambxst reload`); the next palette
   change regenerates `gtk.css` with the import. To get it immediately, change
   the wallpaper once, or append the line by hand this one time:
   `printf '\n@import url("custom.css");\n' >> ~/.config/gtk-3.0/gtk.css`
2. Create `~/.config/gtk-3.0/custom.css` (GTK 3 apps: Thunar, GIMP, Inkscape,
   most Xfce) and/or `~/.config/gtk-4.0/custom.css` (GTK 4 / libadwaita apps).
3. Restart the app you are theming. GTK does not live-reload user CSS.

Because the import comes last, a later `@define-color` wins: `custom.css` can
redefine any colour Ambxst generated. For example, to give GTK apps a
translucent background regardless of the shell's own surface opacity:

```css
@define-color window_bg_color rgba(0, 0, 0, 0.85);
@define-color headerbar_bg_color rgba(0, 0, 0, 0.85);
@define-color view_bg_color rgba(0, 0, 0, 0.85);
```

Hyprland's blur picks translucent GTK windows up automatically; no window rule
is needed.

## Example: a frosted-glass Thunar

`extras/examples/thunar-glass.css` is a complete `~/.config/gtk-3.0/custom.css`
for Thunar 4.20 on adw-gtk3: one glass layer per region (file view, bars,
sidebar), a flat grey selection instead of the accent wash, and the fixes for
the two things Thunar does outside CSS (the selection pill is painted in C from
`theme_selected_bg_color`; exo's icon view always paints its label cells). The
comments in the file explain each rule and the traps found along the way
(never paint `paned > separator`; re-assert transparent rules after painting
`.view`). Colours are for a dark red palette; adjust to taste.

## Changelog

- 1.0.0: initial release, verified on Ambxst 1.3.3 (base af9f8ad4).
