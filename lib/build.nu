let out = $env.out
let lib_target = $'($out)/lib/nushell/($env.package_name)'
mkdir $'($out)/lib/nushell'

let add_path = $env.symlinkjoin_path | path join bin

# __set_env command injects binary dependencies into $env.PATH
# using symlinkJoinPath
#
# __unset_env finds and removes the first entry it meets
# there may be more than one if commands call each other. Then
# they should be popped one by one as a stack
#
# __make_env creates argument for with-env
let set_env_commands = $"
def __make_env [] {
  let path = ($add_path | to nuon)
  [PATH [$path ...$env.PATH]]
}

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
    let script_patched = $source | patch-file | [$in $set_env_commands] | str join
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

def patch-file []: string -> string {
  let file = $in

  let body_spans = $file | find-commands
  let patched_bodies = $body_spans | each {|it|
      $file | str substring $it.from..$it.to
        | patch-command $it.isenv
    }

  # Invert spans
  # e.g. [{1 2} {3 4}] into [{0 1} {2 3} {4 ($file | str length)}]
  let rest_spans = $body_spans
    | each {[$in.from $in.to] }
    | flatten
    | [0 ...$in ($file | str length)]
  let rest_spans = $rest_spans
    | every 2
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

# Find all exported command definitions
# Input: text of script
# Output: table, from - index of opening brace of command body
#   to - index of closing brace of command body
#   isenv - true if command is a `def --env`
def find-commands []: string -> table<from: int to: int isenv: bool> {
  let file = $in
  # Parse matches 'export def <signature>{' any signature up until
  # the opening curly bracket in 'all' group
  # Additionaly matches '--env' in 'env' group
  let normal_symbol = "[^{#'\"`]"
  let comment = '(?:#.*\n)'
  let string = "(?:'[^']*')|(?:\"[^\"]*\")|(?:`[^`]*`)"

  let signature_middle = $"($normal_symbol)|($comment)|($string)"
  let signature = '(?<all>export\s+def\s+(?<env>--env)?(?:' + $signature_middle  + ')+{)'
  $file | parse -r $signature
    | each {|it|
        let from = $file | str index-of $it.all | $in + ($it.all | str length)
        let to = $file | find-block-end $from 
        let isenv = not ($it.env | is-empty)
        {
          from: $from
          to: $to
          isenv: $isenv
        }
      }
}

# Modify command body to set `$env.PATH`
def patch-command [
  is_env: bool
]: string -> string {
  if $is_env {
    # `def --env` commands need special handling to correctly clear
    # `$env.PATH` that may be modified by command itself
    $"\n__set_env | do --env {($in)} | __unset_env\n"
  } else {
    # Non `def --env` commands don't change outside environment and
    # can be wrapped with with-env which is faster than doing __set_env
    # and __unset_env
    $"\nwith-env \(__make_env\) {($in)}"
  }
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
    | reduce --fold { idx: $start_idx depth: 1 state: { name: code } } {|it, acc|
        if $acc.depth == 0 {
          $acc
        } else match $acc.state.name {
          code => { 
            idx: ($acc.idx + 1)
            depth: (match $it {
              '{' => ($acc.depth + 1)
              '}' => ($acc.depth - 1)
              _ => $acc.depth
            })
            state: (match $it {
              '#' => { name: comment }
              "'" => { name: string type: "'" }
              '"' => { name: string type: '"' }
              '`' => { name: string type: '`' }
              _ => { name: code }
            })
          }
          comment => {
            idx: ($acc.idx + 1)
            depth: $acc.depth
            state: (match $it {
              "\n" => { name: code }
              _ => { name: comment }
            })
          }
          string => {
            idx: ($acc.idx + 1)
            depth: $acc.depth
            state: (if $it == $acc.state.type {
              { name: code }
            } else match $it {
              '\' => { name: escape type: $acc.state }
              _ => $acc.state
            })
          }
          escape => {
            idx: ($acc.idx + 1)
            depth: $acc.depth
            state: $acc.state.type
          }
        }
      }
    | get idx
}
