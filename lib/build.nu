let out = $env.out
let lib_target = $'($out)/lib/nushell/($env.package_name)'
mkdir $'($out)/lib/nushell'

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
let set_env_func = $"

def --env __set_env [] {
  let inp = $in
  let path = ($add_path | to nuon)
  if \($env.PATH | last \($path | length\)\) != $path {
    $env.PATH = \($env.PATH | append $path\)
  }
  $inp
}"
log $'Additional $env.PATH = [ ($add_path | str join " ") ]'
      
if ($env.copy | path type) == dir {
  cp -r $env.copy $lib_target
} else {
  mkdir $lib_target
  cp $env.copy $'($lib_target)/mod.nu'
}

let all_scripts = glob $'($lib_target)/**/*.nu'

# Only add __set_env if there is something to add
if not ($add_path | is-empty) {
  log $'"($add_path.0)"'
  for $f in $all_scripts {
    log $'Patching ($f)'
    let source = open --raw $f
    let script_patched = $source | patch-file | [$in $set_env_func] | str join
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

def patch-file []: string -> string {
  let file = $in

  let body_spans = $file | find-functions
  let patched_bodies = $body_spans
    | each {|it| $file | str substring $it.from..$it.to }
    | each { patch-function }

  # Invert spans
  # e.g. [{1 2} {3 4}] into [{0 1} {2 3} {4 ($file | str length)}]
  let rest_spans = $body_spans
    | each {[$in.from $in.to] }
    | flatten
    | [0 ...$in ($file | str length)]
  let rest_spans = $rest_spans | every 2
    | zip ($rest_spans | skip 1 | every 2)
    | each { { from: $in.0 to: $in.1 } }

  # From inverted spans get text that did not make it
  # into $patched_bodies
  let rest_text = $rest_spans 
    | each {|it| $file | str substring $it.from..$it.to }

  # Interleave and join remaining text and patched bodies
  $rest_text
    | zip $patched_bodies
    | flatten
    | [...$in ($rest_text | last )]
    | str join
}

def find-functions []: string -> table<from: int to: int> {
  let file = $in
  $file | parse -r '(export\s+def\s+\S+\s+\[[^]]*\][^{]*{)'
    | get capture0 
    | each {|it| $file | str index-of $it | $in + ($it | str length) }
    | each {|it| $file | find-block-end $it | { from: $it to: $in } }
}

# Modify function body by wrapping existing code in do
# block and adding __set_env call in pipe
# This way values are correctly piped into existing script
def patch-function []: string -> string {
  $"\n__set_env | do {($in)}\n"
}

# Find end of current block
#
# Input: string with nu code
# Output: index of '}' closing block
def find-block-end [
  start_idx: int # Index of '{' starting the block
]: string -> int {
  $in | split chars
    | drop nth ..$start_idx
    | reduce --fold { idx: $start_idx depth: 1 } {|it, acc|
      if $acc.depth == 0 {
        $acc
      } else if $it == '{' {
        { idx: ($acc.idx + 1) depth: ($acc.depth + 1) }
      } else if $it == '}' {
        { idx: ($acc.idx + 1) depth: ($acc.depth - 1) }
      } else {
        { idx: ($acc.idx + 1) depth: $acc.depth }
      }
    }
    | get idx
}
