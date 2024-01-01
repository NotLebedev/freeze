use assert # Assert is part of nushell

def check-jq-installed []: nothing -> nothing {
  assert equal (which jq | length) 1
}

export def --env new-var []: nothing -> nothing {
  check-jq-installed
  $env.QWE = rty
}

export def --env add-to-path []: nothing -> nothing {
  check-jq-installed
  $env.PATH = ($env.PATH | append /qwe/qwe)
}

export def --env clear-path []: nothing -> nothing {
  check-jq-installed
  $env.PATH = []
}
