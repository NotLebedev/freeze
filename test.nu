#!/usr/bin/env nu
export def main [] {
  print $env.PATH
  print Here!
  qweqwe
  cowsay Hello!
}

def qweqwe [] {
  print (which cowsay)
}
