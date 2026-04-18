# Installer Assets

Place the following files here before building the installer:

| File | Format | Size | Used for |
|---|---|---|---|
| `tian.ico` | Windows ICO (multi-size) | 16×16, 32×32, 48×48, 256×256 | Installer window and Start Menu shortcut |

To generate `tian.ico` from a PNG:
```powershell
# Using ImageMagick (winget install ImageMagick.ImageMagick)
magick convert logo.png -define icon:auto-resize="256,48,32,16" tian.ico
```

Once the file is present, uncomment the `SetupIconFile` line in `tian-setup.iss`.
