use foo print-avail
use dependency lol

export def main [] {
  print $env.PATH
  print 'Hello from test!'
  print-avail
  print (cowsay Hello!)
  print (lol)
}
