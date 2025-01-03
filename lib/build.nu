let add_path = $env.symlinkjoin_path | path join bin
log $'Additional $env.PATH is [ ($add_path) ]'

# Copy all files from source as is if source is a directory
# or copy rename to mod.nu if source is a file
if ($env.copy | path type) == dir {
  cp -r --preserve [] $env.copy build
} else {
  mkdir build
  cp --preserve [] $env.copy build/mod.nu
}

let all_scripts = glob build/**/*.nu

# Only patch commands if there are binaries in dependencies
if ($add_path | path exists) {
  log $'"($add_path)"'
  for $f in $all_scripts {
    log $'Patching ($f)'
    let source = open --raw $f
    let script_patched = $source | ^$env.patcher
    rm $f
    $script_patched | save -f $f
  }
}

# Find all nushell script dependencies in lib/nushell inside
# symlinkjoin derivation
let nushell_packages = $env.symlinkjoin_path
  | path join lib nushell
  | if ($in | path exists) {
      ls -a -f $in | get name
    } else { [ ] }

log $'Nushell scripts found in dependencies [ ($nushell_packages | str join " ") ]'

# Find dirs with .nu scripts to add symlinks to nushell script dependencies
let dirs_with_scripts = $all_scripts | path dirname | uniq
for $package in $nushell_packages {
  let link_name = $package | path basename
  for $d in $dirs_with_scripts {
    # TODO: replace this when ln is integrated into nushell
    ^$env.ln -s $package $'($d)/($link_name)' 
  }
}

let lib_target = $'($env.out)/lib/nushell/($env.package_name)'
mkdir ($lib_target | path dirname)
cp -r build $lib_target
