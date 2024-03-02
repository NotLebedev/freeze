use std assert # Assert is part of nushell

export def main []: nothing -> nothing {
  let sample = {
    a: {
      b: [ 1 2 3 4 10 ]
      c: 'Hello, world!'
    }
    d: 1.12
  }

  let updated_with_jq = $sample | to json
    | jq .a.b[4]=5 # Using external binary here
    | from json

  let updated_reference = $sample | update a.b.4 5

  assert equal $updated_with_jq $updated_reference
}
