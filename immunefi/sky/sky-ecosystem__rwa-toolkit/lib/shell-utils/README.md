# CES Shell Utils

Home for Collateral Engineering Services utility shell scripts.

<!-- vim-markdown-toc GFM -->

* [Installation](#installation)
  * [As Dependency](#as-dependency)
  * [From Released Packages](#from-released-packages)
  * [From Source](#from-source)
* [Commands](#commands)
  * [`json-to-env`](#json-to-env)
    * [Requirements](#requirements)
    * [Usage](#usage)
  * [`changelog-to-json`](#changelog-to-json)
    * [Requirements](#requirements-1)
    * [Usage](#usage-1)
* [Contributing](#contributing)
  * [How To](#how-to)
    * [Add a New Utility](#add-a-new-utility)
    * [Make a Release](#make-a-release)
  * [Requirements](#requirements-2)
  * [Code Conduct](#code-conduct)

<!-- vim-markdown-toc -->

## Installation

### As Dependency

The easiest way is to add this repo as a dependency to your own repo:

```bash
git submodule add https://github.com/clio-finance/shell-utils ./lib/shell-utils
```

Then you can reference all utilities through the `./lib/shell-utils/bin/` directory:

```
./lib/shell-utils/bin/json-to-env
```

### From Released Packages

Go to [releases](https://github.com/clio-finance/shell-utils/releases/latest) and download the latest
`ces-shell-utils-x.y.z.tar.gz` file.

Un-tar the release file with:

```bash
tar -xzf ces-shell-utils-x.y.z.tar.gz
```

Run the `install.sh` script:
```bash
cd ces-shell-utils-x.y.z
./install.sh
```

If you want to change the installation location, use the `$PREFIX` env var:

```bash
PREFIX=path/to/installation ./install.sh
```

To uninstall, run the `uninstall.sh` script:
```bash
cd ces-shell-utils-x.y.z
./uninstall.sh
```

### From Source

See the required [dependencies](#requirements-1).

Clone this repo and then run:

```bash
make
make install
```

Commands and documentation will be placed into `$HOME/.local` by default.

Make sure you have `$HOME/.local/bin` in your `$PATH`.

If you want to change the installation location, use the `$PREFIX` env var:

```bash
make
PREFIX=path/to/installation make install
```

To uninstall, run:
```bash
make uninstall
# If you changed $PREFIX during installation you will have to do the same here:
# PREFIX=path/to/installation make uninstall
```

## Commands

### `json-to-env`

#### Requirements

- [`jq`](https://github.com/stedolan/jq)

#### Usage

```man
JSON‐TO‐ENV(1)                             User          Commands
JSON‐TO‐ENV(1)

NAME
       json‐to‐env ‐ manual page for json‐to‐env 0.1.0

SYNOPSIS
       json‐to‐env [‐hvx] [‐f] <file>
       json‐to‐env [‐hvx] [‐f] ‐
       json‐to‐env [‐hvx]

DESCRIPTION
       json‐to‐env  ‐  Converts a JSON file into POSIX shell  en‐
vironment vari‐
       able  declarations  Each  ‘key‘:  ‘value‘   pair  will  be
converted  to  a
       ‘key=value‘  statement.   If  <file> is not provided or is
‘‐‘, it will
       read from stdin.

OPTIONS
       ‐f, ‐‐file
              The path to the file to read from.

       ‐h, ‐‐help
              Show this help text.

       ‐v, ‐‐version
              Show the version.

       ‐x, ‐‐export
              Prepend ’export’ to the generated environment vari‐
ables.

EXAMPLES
       json‐to‐env /path/to/file.json
              Regular usage

       cat /path/to/file.json | json‐to‐env
              Same as above

       json‐to‐env ‐x /path/to/file.jsoni
              Export the variables (‘export VAR=VALUE‘)

       json‐to‐env ‐f /path/to/file.json
              Can use the ‐f option

       json‐to‐env /path/to/file.jsoni
              Or simply a positional argument

       json‐to‐env <<< "{"VAR":"VALUE"}"
              JSON literal

json‐to‐env        0.2.0                        March        2022
JSON‐TO‐ENV(1)
```

### `changelog-to-json`

#### Requirements

- [`jq`](https://github.com/stedolan/jq)
- [`foundry`](https://github.com/foundry-rs/foundry) (preferred, or)
- [`dapp.tools`](http://dapp.tools)

#### Usage

```man
CHANGELOG‐TO‐JSON(1)                       User          Commands
CHANGELOG‐TO‐JSON(1)

NAME
       changelog‐to‐json  ‐  manual  page  for  changelog‐to‐json
0.2.0

SYNOPSIS
       changelog‐to‐json [<changelog_address>]
       changelog‐to‐json [‐hv]

DESCRIPTION
       changelog‐to‐json  ‐  Fetches  the  info from the on‐chain
changelog at
       <changelog_address> and extract it into a JSON  file.   If
<changelog_ad‐
       dress>  is  not  provided,  it  will  attempt to read from
stdin.

OPTIONS
       ‐h, ‐‐help
              Show this help text.

       ‐v, ‐‐version Show the version.

EXAMPLES
       changelog‐to‐json \
         0x7EafEEa64bF6F79A79853F4A660e0960c821BA50
              Fetches the info from CES Goerli MCD

       jq ‐r ’.CHANGELOG’ ’addresses.json’ | changelog‐to‐json
              When the address is extracted  from  another  file,
it  can  be passed in as input

       changelog‐to‐json $(jq ‐r ’.CHANGELOG’ ’addresses.json’)
              This is equivalent to the command above

changelog‐to‐json        0.2.0                  March        2022
CHANGELOG‐TO‐JSON(1)
```

## Contributing

### How To

#### Add a New Utility

Add a new file in the `./bin/` directory. The file should have no extension and it should be self-executable (i.e.:
`#!/bin/bash` for bash scripts, `#!/bin/env python` for python scripts, `#!/bin/env node` for node.js scripts).

Make sure the utility is properly documented and accepts at least the `-h/--help` and `-v/--version` options. See
existing files for examples.

#### Make a Release

**NOTICE:** To be able to run the commands below you are required to have [`github-cli`](https://cli.github.com/)
installed and properly configured.

This repo uses [semver](https://semver.org/). To make a new release, update the `$VERSION` variable in `Makefile` to a
proper value. After that, run in sequence:

```bash
make
make tag
make release
```

At this point, `github-cli` will prompt you about some details to document the release. Go to [releases](https://github.com/clio-finance/shell-utils/releases) for some inspiration.

### Requirements

- [`make`](https://www.gnu.org/software/make/): build tool.
- [`sed`](https://www.gnu.org/software/sed/manual/sed.html): a steam editor.
- [`help2man`](https://www.gnu.org/software/help2man/): generates man files from the `--help` text of commands.
- [`nroff`](https://www.gnu.org/software/groff/): typesetting system that reads plain text mixed with formatting
commands and produces formatted output.

### Code Conduct

TODO.
