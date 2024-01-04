use assert # Assert is part of nushell

def check-jq-installed []: nothing -> nothing {
  assert equal (which jq | length) 1
}

export def sub []: nothing -> nothing {
  check-jq-installed
}

export def 'sub command1' []: nothing -> nothing {
  check-jq-installed
}

export def "sub command2" []: nothing -> nothing {
  check-jq-installed
}

export def `sub command3` []: nothing -> nothing {
  check-jq-installed
}
