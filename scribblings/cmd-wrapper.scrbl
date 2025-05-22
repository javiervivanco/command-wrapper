#lang scribble/manual
@require[@for-label[racket/base racket/contract cmd-wrapper]]
@require[scribble/core scribble/racket]

@title{cmd-wrapper}
@author{javiervivanco}

@defmodule[cmd-wrapper]

Package Description Here
@section{Functions}

@defproc[(make-command-wrapper [command-name string?] [std-out (-> any/c any/c)]) procedure?]
Creates a command wrapper for the given command name. The `std-out` function is called with the command arguments and the standard output of the command.

@defproc[(-- [args (listof any/c)]) bytes?]
Formats a list of arguments into a byte string suitable for command-line execution.
It handles different types of arguments:
@itemlist[
  @item{Strings and numbers are enclosed in double quotes.}
  @item{Lists are recursively processed, with elements joined by spaces.}
  @item{Booleans are converted to "true" or "false".}
  @item{Bytes and paths are converted to their string representation.}
  @item{Empty lists and void values are represented as a space.}
]
The function uses a pattern matching approach to format arguments based on their structure, supporting single arguments, key-value pairs, and flags.
For example:
@itemlist[
  @item{`(-- '(\"foo\" \"bar\"))` results in `\"--foo bar\"`}
  @item{`(-- '(foo))` results in `\"--foo\"`}
  @item{`(-- '(foo \"bar\"))` results in `\"--foo=bar\"`}
  @item{`(-- '(\"f\" \"baz\"))` results in `\"-f baz\"`}
  @item{`(-- 'f)` results in `\"-f\"`}
]

@section{More Examples}

@subsection{Interacting with Git}

You can use `make-command-wrapper` to interact with `git` commands.

@racketblock[
(require cmd-wrapper)

(define (git-output-handler cmd-info exit-code stdout-result)
  (printf "Git command: ~s~n" cmd-info)
  (unless (zero? exit-code)
    (eprintf "Git command failed with exit code: ~a~n" exit-code))
  (printf "Output:~n~a" stdout-result))

(define git (make-command-wrapper "git" git-output-handler))

;; Example: Get current git status
(git 'status)

;; Example: Get short git status
(git 'status #:short #t)

;; Example: Log last 2 commits
(git 'log #:max-count 2 #:oneline #t)

;; Example: Create and checkout a new branch (conceptual)
;; Note: For actual branch creation, you might want a more robust handler
;; or separate wrappers for commands with significant side effects.
(git 'checkout #:"b" "new-feature-branch")
(git 'branch) ; To see current branches
]

This demonstrates how to define a handler and create a `git` wrapper. You can then call various git subcommands with their respective arguments.
Remember that the `std-out` handler you provide to `make-command-wrapper` will be called with the results of each command execution.
