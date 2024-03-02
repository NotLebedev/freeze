use std assert # Assert is part of nushell

export def simple-pipe []: string -> string {
  jq .a.b | from json
}

export def pipe-complex []: record<a: string b: int> -> record<c: string d: int> {
  to json | jq .a | from json | {c: $in d: 3}
}

export def pipe-let []: string -> string {
  let inp = $in
  assert equal (which jq | length) 1
  $in
}
