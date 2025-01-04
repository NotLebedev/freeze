use std assert
use dep f2

export def lib_test [] {
  assert equal (f2) "f2"

  const path_self = path self | path dirname

  let content = open $"($path_self)/content.txt"
  assert equal $content content
}