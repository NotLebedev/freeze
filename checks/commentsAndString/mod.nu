use assert # Assert is part of nushell

def check-jq-installed []: nothing -> nothing {
  assert equal (which jq | length) 1
}

export def test0 [
  arg? # Comment with {}
]: nothing -> nothing {
  check-jq-installed
}

export def test1 [
  arg = '}'
  arg2 = '{'
] {
  check-jq-installed
}

export def test2 [] {
  # qwe {
  check-jq-installed
}

export def test3 [] {
  let a = '}'
  let a = '{'
  check-jq-installed
}

export def test4 [] {
  let a = "}"
  let a = "{"
  let a = "\"{"
  check-jq-installed
}

export def test5 [] {
  let a = [`}`]
  let a = [`{`]
  check-jq-installed
}
