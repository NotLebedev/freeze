# 🥶 Freeze

Turn your [nushell](https://www.nushell.sh/) scripts into [nix](https://nixos.org/) packages.

## Warning

This project is really not complete. But feel free to try it out. Pin your inputs and nix will
cover you. But take care when updating, things might (and will) be changing and breaking.

## Using freeze

Freeze is a flake providing an overlay with a few functions to create packages and executables.
Install it by adding overlay to your pkgs like this:

```nix
inputs.freeze.url = "github:NotLebedev/freeze"; # Add to flake input

...

pkgs = import nixpkgs {
  inherit system;
  overlays = [
    freeze.overlays.default # Add freeze to overlays when importing nixpkgs
  ];
};
```

alternatively if you need freeze one time, not for the entire flake, you can use

```nix
pkgsWithFreeze = pkgs.extend freeze.overlays.default
```

In nixos configuration or [home manager](https://nix-community.github.io/home-manager/index.html)
add overlay to `nixpkgs.overlays`:

```nix
nixpkgs.overlays = [ freeze.overlays.default ];
```

⚠️ Warning, if you are using combined configuration of nixos and home manager you must use option
of nixos configuration, not home manager one. Otherwise nothing is added to `pkgs` for some
reason.

Freeze also includes a pretty sizeable binary, which may take a long time to build. Consider adding
[cachix](https://notlebedev.cachix.org/) binary cache as described on page, or directly to your
nixos configuration like so:

```nix

nix.settings = {
  substituters = [ "https://notlebedev.cachix.org" ];
  trusted-public-keys = [ "notlebedev.cachix.org-1:hGfF7W2IxXfxf9fiDrrUhJH6pypRq5QMNgJ7BO9vMAQ=" ];
};
```

### Packaging functions

With overlay installed `pkgs.nushell-freeze` has this functions:

- `buildNuPackage` - package nushell scripts. Automatically manages binary dependencies and
  dependencies on other nushell scripts.
- `withPackages` - create a nushell wrapper with specified packages available to `use`.
- `wrapScript` - turn a nushell script into an executable.

### Packages overlay

Additionally freeze provides overlay with some pre-packaged nushell scripts:

```nix
nixpkgs.overlays = [ freeze.overlays.packages ];
```

All provided packages are available under `nushell-freeze.packages`. See `packages` directory for
all available packages. Here are some examples:

```nix
# Entire https://github.com/nushell/nu_scripts as a package
# Use git-completions script with `use nu_scripts/completions/git/git-completions.nu *`
nushell-freeze.packages.nu_scripts

# One file from nu_scipts as its own package named git-completions
# Use it in nushell with `use git-completions *` (sole file is renamed to mod.nu for convinience)
# Unlike nu_scripts package nothing else is added to `$env.NU_LIB_DIRS` when installing this
# package
nushell-freeze.packages.from_nu_scripts "git-completions" "custom-completions/git/git-completions.nu"
```

`nu_scripts` repository is an input of this flake, thus if you want to use a different revision you
may overwrite input of this flake:

```nix
{
  inputs = {
    # Nu scripts input of your flake. Updates independently from freeze
    nu_scripts = {
      url = "github:nushell/nu_scripts";
      # Important, nu_scripts is not a flake
      flake = false;
    };

    freeze = {
      url = "github:NotLebedev/freeze";
      # Replace default freeze version of nu_scripts with one specified in
      # your flake.lock file
      inputs.nu_scripts.follows = "nu_scripts";
    };
  };

  # ...
}
```

### Home manger module

This flakes also provides a home manager module to add freeze packages to nushell `env.nu` file. To
use this module add it to `home-manager.sharedModules` in NixOS configuration or simply import it
in home manager:

```nix
# Available in nixos configuration.nix file if home manager is installed as NixOS module
sharedModules = [
  freeze.homeManagerModule
];

# Or import in home manager configuration
imports = [
  freeze.homeManagerModule
];
```

now option `programs.nushell.freeze-packages` is available. All packages in the list will be added
to `$env.NU_LIB_DIRS` in `env.nu` and available to use in shell:

```nix
programs.nushell.freeze-packages = [
  freeze.packages.nu-git-manager
];
```

Usable in shell like:

```nu
use nu-git-manager *
gm --help
```

## Design considerations

Here are some thoughts that I had while creating this project.

### Whats the need for `__set_env`/`__unset_env`/patching?

_Short_: To unclutter path and behave in a more nix way.

_Long_: In nix dependencies of packages dont get in path. This prevents clutter and allows multiple
version to coexist. Instead everything must point to `/nix/store`. If script is written in nix
one can call to binaries like `${pkgs.hello}/bin/hello` and nix will automatically expand this
to path into store. However if one needs to package an existing script (and does not want
to turn it into nix expression) this approach is unsuitable.

Another way, that is more commonly used with existing scripts is
[makeWrapper](https://github.com/NixOS/nixpkgs/blob/9a255aba3817d477e0959b53e9001d566bfb3595/pkgs/build-support/setup-hooks/make-wrapper.sh)
script that allows to create a wrapper around existing scripts that sets (or unsets) some
environment variables. In this case `$env.PATH` is of interest. Unlike bash scripts nushell ones
can have more then one command inside them and hove some tricky behavior with `def --env`.

To solve this scripts are patched (but only if package has dependencies with `bin` directory).
The straightforward approach is to wrap command body in `with-env`:

```nu
export def test [ ... ]: input -> output {
  commands
}

# Turned into

export def test [ ... ]: input -> output { # Signature remains untouched
  with-env (__make_env) { # __make_env is a helper command that adds entries to `$env.PATH`
    commands # Run original commands inside this block
  }
}
```

It works fine with simple commands but a more clever approach is needed for `def --env`:

```nu
export def --env test [ ... ]: input -> output {
  commands
}

# Turned into

export def --env test [ ... ]: input -> output { # Signature remains untouched
  __set_env | do --env { # Load dependencies to $env.PATH and pipe input through
    commands # Run original commands inside a do block
  } | __unset_env # Unload dependencies from $env.PATH and pipe output through
}
```

This approach solves several problems. First wrapping original code in `do --env` helps
with handling input and output of command. Without this it becomes tricky to handle
input for commands beginning with `let`. Using `do --env` instead of `with-env` allows to correctly
handle changes of environment inside `def --env` functions. Also because such functions may edit
`$env.PATH` special logic is needed in `__unset_env`. To work around this issue all binary
dependencies are packaged into one
[symlinkJoin](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-symlinkJoin) derivation
and `__set_env` adds one entry to `$env.PATH` and `__unset_env` removes it (by value, not index
in PATH to handle modifications of PATH by original command correctly). This solution allows
seamless handling of most cases.

To perform these code modification a patcher written in rust based on nushell internal crates is
used. It is easier to parse code this way and results of patching are always consistent with how
nushell behaves. See [lib/patcher](lib/patcher) for code.

### What to do for `use` of other nushell scripts?

_Short_: Add symlinks to all dependencies into derivation, kinda like symlink join.

_Long_: In case of `$env.NU_LIB_DIRS` situation is different. Unlike `$env.PATH` it is not handled
dynamically. Instead `use`s are evaluated during parsing of scripts as described
[here](https://www.nushell.sh/book/how_nushell_code_gets_run.html). Therefore adding to
`$env.NU_LIB_DIRS` at runtime like in case of `$env.PATH` is pointless. Luckily if a script
`hello.nu` is in same directory current script file one can `use hello.nu` it directly (unlike
binaries, which would need to be called as `./hello`). Therefore it would be enough to just
symlink nushell-script dependencies somewhere near script that uses it.

The only remaining question is how to reference specific package. The first idea is
`use <package>/hello.nu` (or `use <package>` if it has `mod.nu` in root). And the first idea is a
good one. Package name is not specific to nix, [nupm](https://github.com/nushell/nupm) does the
same thing. Also this promotues usage of `mod.nu` and `use` derectives without
the `.nu` postfix which look nicer.

To implement this derivation adds symlinks to all packages in this format to every directory
that contains `.nu` files when packaging. So an example project with structure like:

```
project/
  - mod.nu
  - subdir/
    - part.nu
```

with dependencies `foo` and `bar` will transform to:

```
project/
  - mod.nu
  - foo/ -> /nix/store/<hash>-foo/lib/nushell/foo
  - bar/ -> /nix/store/<hash>-bar/lib/nushell/bar
  - subdir/
    - part.nu
    - foo/ -> /nix/store/<hash>-foo/lib/nushell/foo
    - bar/ -> /nix/store/<hash>-bar/lib/nushell/bar
```

This is esseintially equivalent to putting `foo` and `bar` into `.config/nushell` which is part
of `$env.NU_LIB_DIRS` by default. Or similar to how
[nupm](https://github.com/nushell/nupm/blob/f7c0843f4d667194beae468614a46cc8d72cc5db/docs/design/README.md#dependency-handling-toc)
puts stuff in `NUPM_HOME/overlays`. But with a key difference, while being equivalent this is,
in nix style, exclusive to package, preventing collisions between different packages.

### Closing thoughts

Ultimately _I_ think that handling of dependencies is done well. It
is simple, needs zero modifications to existing scripts (everything is contained in `flake.nix`)
and allows simple convention, similar to nupm with `use` of other packages.

The only problem is cumbersome patching for binary dependencies (addition of `__set_env`). Some
bugs in patching and unaccounted behavior of scripts is certain to exist. Suggestions, bug reports
and fixes are welcome!
