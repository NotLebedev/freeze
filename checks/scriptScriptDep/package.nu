use 'dependency0'
use 'dependency1'

export def main [] {
  if (dependency0) != 'dependency0' {
    error make { msg: 'Something wrong with dependency0' }
  }

  if (dependency1) != 'dependency1' {
    error make { msg: 'Something wrong with dependency1' }
  }
}
