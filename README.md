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
On macOS it also shows an ImageMagick path field, since that's the only platform where
Homebrew's install location isn't predictable.
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

- [ImageMagick](https://imagemagick.org/) version 6 or 7. The script picks a default
  executable for your platform: Homebrew's `magick` on macOS (Intel or Apple Silicon),
  the distro package on Linux (`magick` for version 7, the standalone `montage` for
  version 6), or `magick` on PATH on Windows. On macOS, where the install location is
  the least predictable, you can override it in the dialog.
- Verified to work on MacOS. It might work for Windows and Linux.

## License

MIT — see [LICENSE](LICENSE).
