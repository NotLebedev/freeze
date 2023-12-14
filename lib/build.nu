let out = $env.out
let lib_target = $'($out)/lib/nushell/($env.package_name)'
mkdir $'($out)/lib/nushell'

# def --env is not allowed, because it will polute outer
# environment with path of package
let main_head_regex = 'def\s+?main\s+\[[^]]*\][^{]*{'
let extern_head_regex = 'export\s+def\s+\S+\s+\[[^]]*\][^{]*{'

# Match either `def main [...] {` or any `export def ... [...] {` 
let patch_head_regex = $"\(?:($main_head_regex)\)|\(?:($extern_head_regex)\)"
let add_set_env = "$0\n__set_env"

let add_path = $env.packages_path | from nuon
  | filter {|it| ($it | str length) > 0}
  | each { path join bin }
  | filter { path exists }
  | filter { (ls $in | length) > 0 }

# __set_env function checks if env was set for current package
# by checking if PATH ends with dependencies of this package
# This prevents $add_path added multiple times if exported commands
# call each other. There may still be a problem if command from
# one package calls command from another and then back
let set_env_func = $"def --env __set_env [] { 
  let path = ($add_path | to nuon)
  if \($env.PATH | last \($path | length\)\) != $path {
    $env.PATH = \($env.PATH | append $path\)
  }
}"
log $'Additional $env.PATH = [ ($add_path | str join " ") ]'
      
if ($env.copy | path type) == dir {
  cp -r $env.copy $lib_target
} else {
  mkdir $lib_target
  cp $env.copy $lib_target
}

let all_scripts = glob $'($lib_target)/**/*.nu'

# Only add __set_env if there is something to add
if not ($add_path | is-empty) {
  log $'"($add_path.0)"'
  for $f in $all_scripts {
    log $'Patching ($f)'
    let source = open --raw $f
    let patched_with_call = $source | str replace -a -r $patch_head_regex $add_set_env
    let script_patched = [$patched_with_call $set_env_func] | str join
    rm $f
    $script_patched | save -f $f
  }
}

let nushell_packages = $env.packages_path | from nuon
  | filter {|it| ($it | str length) > 0}
  | each { path join lib/nushell }
  | filter { path exists }
  | filter { (ls $in | length) > 0 }

log $'Nushell scripts forund in dependencies [ ($nushell_packages | str join " ") ]'

# Find dirs with .nu scripts to add symlinks to nushell script dependencies
let dirs_with_scripts = $all_scripts | path dirname | uniq
for $package in $nushell_packages {
  # Each nushell dir may contain more then one package, theoretically
  # Futureproofing, kinda
  let imports = ls $package | get name
  for $import in $imports {
    let link_name = $import | path basename
    for $d in $dirs_with_scripts {
      # Uutils are currently intergrated into nushell so ixpect this to
      # be easier to replace later
      ^$env.ln -s $import $'($d)/($link_name)' 
    }
  }
}
