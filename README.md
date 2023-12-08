# 🥶 Freeze
Turn your [nushell](https://www.nushell.sh/) scripts into [nix](https://nixos.org/) packages

## Warning
This project is really not complete. But feel free to try it out. Pin your inputs and nix will
cover you. But take care when updating, things might (and will) be changing and breaking.

## Using freeze
Freeze is a flake providing an overlay with a few functions to create packages, executables
and (soon) dev environments based on nushell. Install it by adding overlay to your pkgs
like this:
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

With overlay installed `pkgs.nushell-freeze` has this functions:
* `buildNuPackage` - package nushell scripts. Automatically manages binary dependencies and
dependencies on other nushell scripts.
* `withPackages` - create a nushell wrapper with specified packages available to `use`
* `wrapScript` - turn a nushell script into an executable

## Design considerations
Here are some thoughts that I had while creaating this project.

### Why use nuenv to build derivations?
*Short*: It's cool and its nushell

*Long*: I really don't like sh derivative shells. Before I discovered nushell I did not touch shell
much and was really annoyed when I needed to. When I discovered nushell I fell in love with it
and started using shell a lot. With some time I understood and became more familiar with sh/bash
too. But ultimately I'm not torturing myself with bash on free time, I much rather toy with nushell.

### Whats the need for `__set_env`/export patching?
*Short*: To allow multiple scripts reference multiple versions of the same binary

*Long*: In nix installed packages dont get in path. This prevents clutter and allows multiple
version to coexist. Instead everything must point to `/nix/store`. If script is written in nix
one can call to binaries like `${pkgs.hello}/bin/hello` and nix automatically exapnds this
to path into store. However if one needs to package an existing script (and does not want
to turn it into nix expression) this is unacceptable. 

There ore other ways. One of them is
[symlinkJoin](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-symlinkJoin). It creates
a new derivation which symlinks all parts of it in one place. This works as ling as parts
do not collide. If one script required `hello-2.10` and another `hello-2.9` then two symlinks
to `hello` need to be made. Which is a problem.

Another solution (and the one chosen) is to update path for each separate script via some form
of wrapper. Here a `__set_env` function is created for each package, which adds all its
binary dependencies and is called at the start of each entry point. This approach is similar
to what is described
[here](https://www.nushell.sh/book/modules.html#setting-environment-aliases-conda-style), except
for each individual script and done automatically in nix derivation. If path was not already set
it prepends (to overwrite) it to existing PATH. 

One limitation of this approach is `def --env` may clutter path and thus it is disallowed. Non-env
commands will revert to old env state on exit and thus modifications to path are limited to scope
of command (and called subcommands, this is desired, because subcommand can recieve a closure
that will call back to some binary used by caller and it needs to be in path).

### Why is this not done for `use` of nushell scripts?
*Short*: Nushell searches for binaries to run dynamically searching path. Howver all paths
used in `use` need to be kwnown before parsing.

*Long*: With binary commands if `$env.PATH` is modified at runtime nushell will find binary
by searching through it at runtime. The same is not true about `$env.NU_LIB_DIRS` and `use`.
When first use is called, entire chain of uses is evaluated at parse time, as described
[here](https://www.nushell.sh/book/how_nushell_code_gets_run.html). The real implication here
is that modifying `$env` wich is not a
[constatnt](https://www.nushell.sh/book/variables_and_subexpressions.html#constant-variables)
can only be done at runtime. And so each package can not add additional entries to
`NU_LIB_DIRS` as it is evaluated to search among dependencies.

### Well, what to do about this, really?
*Short*: Use `symlinkJoin`-like approach, which we discarded earlier.

*Long*: Here situation is different. If a binary, say `hello` is in directory near the script
even calling it using `./hello` is less then ideal. But binaries are searched in this way relative
to pwd, not location of script. Luckily `use` does not have any of this problems. If a `hello.nu`
is near current script file one can `use hello.nu` as if it was in `$env.NU_PATH`.

The only remaining question is how to reference specific package. The first idea is 
`use <package>/hello.nu` (or `use <package>` if it has `mod.nu` in root). And the first idea is a
good one. Package name is not specific to nix, [nupm](https://github.com/nushell/nupm) does the
same thing. Also this promotues usage of `mod.nu` and `use` derectives without
the `.nu` postfix which look nicer.

To implement this derivation adds symlinks to all packages in this format to every directory
that contains `.nu` files when packaging. When creating devshells or home manager configuration
`$env.NU_LIB_DIRS` could be set. So an example project with structure like:
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
  - foo/ -> /nix/store/<hash>-foo-0.0.1/lib/nushell/foo
  - bar/ -> /nix/store/<hash>-bar-0.0.1/lib/nushell/bar
  - subdir/
    - part.nu
    - foo/ -> /nix/store/<hash>-foo-0.0.1/lib/nushell/foo
    - bar/ -> /nix/store/<hash>-bar-0.0.1/lib/nushell/bar
```
This is esseintially equivalent to putting `foo` and `bar` into `.config/nushell` which is part
of `$env.NU_LIB_DIRS` by default. Or similar to how
[nupm](https://github.com/nushell/nupm/blob/f7c0843f4d667194beae468614a46cc8d72cc5db/docs/design/README.md#dependency-handling-toc)
puts stuff in `NUPM_HOME/overlays`. But with a key difference, while being equivalent this is,
in nix style, exclusive to package, preventing collisions between different packages.

### Closing thoughts
Ultimately *I* think that handling of dependencies is done well. It
is simple, needs zero modifications to existing scripts (everything is contained in `flake.nix`)
and allows simple convention, similar to nupm with `use` of other packages.

The only problem is cumbersome patching for binary dependencies (addition of `__set_env`). While
the only real problem is no support for `def --env`, the general hackiness of this approach bothers
me. Suggestions are welcome!
