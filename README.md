# moho-scripts

Lua scripts I've written for [Moho](https://moho.lostmarble.com/), mostly to fill gaps in my own
workflow. Right now there's only one, but the repo is set up so more can be added later.

## Export Sprite Sheet

`Menu/Export/DW_ExportSpriteSheet.lua`

Renders a frame range from the current document to PNGs and then packs them into a single
near-square sprite sheet. Handy for getting Moho animation into a game engine or anything
else that wants frames laid out on a grid.

It shows a small dialog first: start/end frame, output folder, sheet filename, and a creator
name that gets embedded in the script metadata. Values you type are remembered between runs.
If you don't set an output folder, it defaults to wherever the project is saved (so save the
project first, or the script will complain).

The frames are rendered into a temp folder, the sheet is packed with ImageMagick's `montage`,
and the temp folder is deleted afterwards. The grid is sized to the frame count so there are
no empty rows at the bottom. If packing fails, the rendered frames are kept so you can look
at them.

### Installation

The easy way: in Moho, go to the Scripts menu, click "Install Script...", then "Select A Script
Folder" and pick this repo's folder. That installs the scripts immediately — no restarting Moho —
and overwrites any previously installed versions, so it's also the way to update after pulling
changes.

Alternatively, drop the file into your Moho scripts folder by hand, keeping the folder structure:

```
<Moho scripts folder>
└── Menu
    └── Export
        └── DW_ExportSpriteSheet.lua
```

### Requirements

- [ImageMagick](https://imagemagick.org/) — the script defaults to `/usr/local/bin/magick`
  (where Homebrew puts it on an Intel Mac). If yours lives elsewhere, set the path in the
  dialog.
- macOS, in practice. The temp folder handling and shell commands assume a Unix-y system.

## License

MIT — see [LICENSE](LICENSE).
