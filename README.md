# dragalia-data-downloader

Dart CLI tool for downloading and pre-process Dragalia Lost game assets.

### Prerequisites

#### `.NET Core 3.1+`

This can be downloaded via https://dotnet.microsoft.com/download/dotnet-core/3.1.

Enter this command in the terminal to ensure the .NET Core SDK is installed:

```commandline
dotnet
```

-------

Make sure the directory structure looks like this:

```
---- (root)
  |---- dldump.exe
  |---- config.json (dumping config)
  |---- Decrypt.dll (manifest file decryption)
  |---- BouncyCastle.Crypto.dll (dependency for Decrypt.dll)
  |---- Decrypt.deps.json (necessary file for Decrypt.dll)
  |---- Decrypt.runtimeconfig.json (necessary file for Decrypt.dll)
  |---- as (config for asset studio)
    |---- action.json (config for exporting the action files)
    |---- animation.json (config for exporting the animation clips)
    |---- icons.json (config for exporting the icons)
    |---- localized.json (config for exporting the localized assets, for example, text label)
    |---- manifest.json (config for exporting the manifest files)
    |---- master.json (config for exporting the common master assets)
    |---- ui.json (config for exporting the UI elements, for example, in-game buff icons)
    |---- unitdetail.json (config for exporting the detailed unit images)
  |---- AssetStudio (asset exporting)
    |---- (AssetStudio files)
```

Errors occur if the directory structure does not look like this.

Note that there are some additional files, including `AssetStudioCLI.exe` and its dependencies in the `AssetStudio`.

Therefore, it is required to use the AssetStudio files directly provided by this repository,
instead of the one from [the original repository](https://github.com/Perfare/AssetStudio).

### Usage

Enter this in the terminal to check the usage:

```commandline
dldump
```