let out = $env.out
let lib_target = $'($out)/lib/nushell/($env.package_name)'
mkdir $'($out)/lib/nushell'

let add_path = $env.symlinkjoin_path | path join bin

# __set_env function injects binary dependencies into $env.PATH
# using symlinkJoinPath
# __unset_env finds and removes the first entry it meets
# there may be more than one if commands call each other. Then
# they should be popped one by one as a stack
let set_env_func = $"

def --env __set_env [] {
  let inp = $in
  let path = ($add_path | to nuon)
  $env.PATH = [ $path ...$env.PATH ]
  $inp
}

def --env __unset_env [] {
  let inp = $in
  let idx = $env.PATH | enumerate
    | where item == ($add_path | to nuon)
    | get index?.0?

  if $idx != null {
    $env.PATH = \($env.PATH | drop nth $idx\)
  }
  $inp
}"
log $'Additional $env.PATH is [ ($add_path) ]'

# Copy all files from source as is if source is a directory
# or copy rename to mod.nu if source is a file
if ($env.copy | path type) == dir {
  cp -r $env.copy $lib_target
} else {
  mkdir $lib_target
  cp $env.copy $'($lib_target)/mod.nu'
}

let all_scripts = glob $'($lib_target)/**/*.nu'

# Only patch commands if there are binaries in dependencies
if ($add_path | path exists) {
  log $'"($add_path)"'
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

log $'Nushell scripts found in dependencies [ ($nushell_packages | str join " ") ]'

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
  # Parse matches 'export def <signature>{' any signature up until
  # the opening curly bracket
  $file | parse -r '(export\s+def[^{]+{)'
    | get capture0 
    | each {|it| $file | str index-of $it | $in + ($it | str length) }
    | each {|it| $file | find-block-end $it | { from: $it to: $in } }
}

# Modify function body by wrapping existing code in do
# block and adding __set_env __unset_env call in pipe
# This way values are correctly piped into existing script
def patch-function []: string -> string {
  $"\n__set_env | do --env {($in)} | __unset_env\n"
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
    # Count parity of curly brackets until all are closed (depth 0)
    # Then just skip rest of input
    | reduce --fold { idx: $start_idx depth: 1 } {|it, acc|
      if $acc.depth == 0 {
        $acc
      } else {
        { 
          idx: ($acc.idx + 1)
          depth: (match $it {
            '{' => ($acc.depth + 1)
            '}' => ($acc.depth - 1)
            _ => $acc.depth
          })
        }
      }
    }
    | get idx
}
