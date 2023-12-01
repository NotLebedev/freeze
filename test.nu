#!/usr/bin/env nu
export def main [] {
  print $env.PATH
  print Here!
  print-avail
  cowsay Hello!
}

def print-avail [] {
  print (which cowsay)
  print (which ddate)
  print (which rg)
}
