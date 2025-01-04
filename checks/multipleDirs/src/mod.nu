use std assert
use dep f1
use lib lib_test

export def test [] {
    assert equal (f1) "f1"
    lib_test
}