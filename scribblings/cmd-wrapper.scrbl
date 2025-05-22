#lang scribble/manual
@require[@for-label[racket/base racket/contract cmd-wrapper]]
@require[scribble/core scribble/racket]

@title{cmd-wrapper}
@author{javiervivanco}

@defmodule[cmd-wrapper]

This module provides a way to create wrappers for command-line commands.
It allows defining a base command and then calling it with subcommands, positional arguments, and keyword arguments.

@section{Main Functions}

@defproc[(make-command-wrapper [command-name string?] [process-out (-> (listof any/c) exact-integer? string? any/c)]) procedure?]
Creates a wrapper procedure for the given @racket[command-name].
The @racket[command-name] is the base command to execute (e.g., @racket["git"], @racket["echo"]).
The @racket[process-out] function is a callback function that is invoked after the command executes. It receives three arguments:
@itemlist[
  @item{@racket[cmd-info]: A list containing the subcommand (if any), a list of keywords, a list of keyword values, and a list of remaining arguments passed to the wrapper.}
  @item{@racket[exit-code]: The exit code of the executed command.}
  @item{@racket[stdout-result]: A string with the standard output of the command.}
]
The procedure returned by @racket[make-command-wrapper] is a keyword procedure. It accepts:
@itemlist[
  @item{Keyword arguments (e.g., @racket[#:name "value"]). These are transformed into @racket["--name value"] on the command line.}
  @item{An optional subcommand (as a string or symbol, e.g., @racket['status] or @racket["status"]). This will be the first argument after the main command.}
  @item{Remaining positional arguments (e.g., @racket["arg1"] @racket["arg2"]). These follow the subcommand (if present) and keyword arguments.}
]
The command is constructed by concatenating @racket[command-name], the subcommand (if provided), the formatted keyword arguments, and the formatted remaining arguments.
It is then executed using @racket[do-system] (which internally uses @racket["/bin/sh -c"]).

The @racket[process-out] callback receives @racket[cmd-info] as a list with the following structure: @racket[(list subcommand kws kw-args rest)].
For example, if the wrapper is called as @racket[(my-cmd #:option "val" "sub" "arg1")], then @racket[cmd-info] will be @racket[("sub" (#:option) ("val") ("arg1"))].
If called as @racket[(my-cmd "sub" "arg1")], @racket[cmd-info] will be @racket[("sub" () () ("arg1"))].
If called as @racket[(my-cmd #:opt1 "v1" #:opt2 "v2" "sub" "arg1" "arg2")], @racket[cmd-info] will be @racket[("sub" (#:opt1 #:opt2) ("v1" "v2") ("arg1" "arg2"))].
The order of keyword arguments in @racket[kws] and @racket[kw-args] is preserved as passed.

@bold{Usage Example:}
@racketblock[
(define (my-processor cmd-info exit-code stdout)
  (printf "Command Info: ~s~n" cmd-info)
  (printf "Exit Code: ~s~n" exit-code)
  (printf "Stdout: ~s~n" stdout)
  stdout)

(define echo (make-command-wrapper "echo" my-processor))

;; Call: (echo #:prefix "Output:" "Hello" "World")
;; cmd-info will be: ("Hello" (#:prefix) ("Output:") ("World"))
;; Command executed: echo Hello --prefix "Output:" "World"
(echo #:prefix "Output:" "Hello" "World")
]


@defproc[(-- [args (listof any/c)]) bytes?]
A helper function to format individual arguments or key-value pairs into byte strings suitable for command-line arguments.
Primarily for internal use or for constructing parts of commands manually if needed.
Converts symbols and strings into formats like @racket[#"--option value"] or @racket[#"-f value"].
Values are formatted using the internal @code{arg->cmd} function.

@section{Argument Formatting with @code{arg->cmd}}

The (unexported) function @code{arg->cmd} is used internally by @code{build-args} (which in turn is used by @racket[make-command-wrapper]) and by the @racket[--] helper function to convert Racket values into string representations suitable for the command line. Its behavior is as follows:
@itemlist[
  @item{@bold{Strings and Numbers:} Enclosed in double quotes (e.g., @racket["hello"] becomes @racket["\"hello\""], @racket[123] becomes @racket["\"123\""]).}
  @item{@bold{Booleans:} @racket[#t] becomes @racket["true"], @racket[#f] becomes @racket["false"].}
  @item{@bold{Lists:} Their elements are recursively processed and joined with spaces. An empty list becomes a single space (@racket[" "]). (e.g., @racket['("a" "b")] becomes @racket["\"a\" \"b\""]).}
  @item{@bold{Bytes and Paths:} Converted directly to their string representation (e.g., @racket[#"bytes"] becomes @racket["bytes"], @racket[(build-path "a" "b")] becomes @racket["a/b"] or @racket["a\\b"] depending on the OS).}
  @item{@bold{Null and Void:} Converted to a single space (@racket[" "]).}
  @item{@bold{Other Types:} Cause an error.}
]
This formatting ensures that arguments are passed to system commands in a way that is generally safe and predictable. The resulting strings from @code{arg->cmd} are then joined by spaces by @code{build-args} to form the final command string part for @code{do-system}.

@section{Complex Example: Git Wrapper}

Below is an example of how a wrapper for the @racket[git] command can be created and used:

@racketblock[
(require cmd-wrapper)

;; A simple output handler for git
(define (git-result-handler cmd-info exit-code stdout)
  (printf "== Git Command Executed ==~n")
  (printf "Cmd Info: ~s~n" cmd-info)
  (printf "Exit Code: ~s~n" exit-code)
  (printf "STDOUT:~n%s~n" stdout)
  (if (zero? exit-code)
      (string-split stdout "\n") ; Returns lines of output as a list on success
      #f)) ; Returns #f on error

(define git (make-command-wrapper "git" git-result-handler))

;; Get current git status
;; cmd-info: ("status" () () ())
(git 'status)

;; Get short git status (git status --short)
;; cmd-info: ("status" (#:short) (#t) ())
(git #:short #t 'status) ;; Also (git 'status #:short #t)

;; View the last 2 commits, one line
;; cmd-info: ("log" (#:max-count #:oneline) (2 #t) ())
(git 'log #:max-count 2 #:oneline #t)

;; Try to create a new branch (this is for demonstration only,
;; the actual command might need more specific error handling if the branch already exists)
;; cmd-info: ("checkout" (#:b) ("my-new-feature") ())
(git 'checkout #:b "my-new-feature")

;; cmd-info: ("branch" () () ())
(git 'branch)
]

This example illustrates how @racket[make-command-wrapper] facilitates interaction with complex command-line utilities like @racket[git], handling the construction of the command string and allowing custom processing of the output.
The flexibility in the order of subcommands and keyword arguments (as seen in @racket[(git #:short #t 'status)]) is a feature of the generated keyword procedure.
The @racket[cmd-info] list passed to the handler provides a structured way to see how the wrapper was called.
The actual command string executed by @racket[do-system] is formed by @racket[command-name], followed by the subcommand (if any), then all keyword arguments formatted (e.g., @racket["--key value"]), and finally all positional arguments. For example, @racket[(git 'log #:max-count 2 #:oneline #t)] would result in a command string like @racket["git log --max-count "2" --oneline "true""].
Note that the @racket[build-args] function, used internally, places the subcommand first, then keyword arguments, then rest arguments.
So, for @racket[(echo #:prefix "Output:" "Hello" "World")], the arguments to @racket[string-join] in @racket[make-command-wrapper] would be @racket[("Hello" "--prefix "Output:"" ""World"")], resulting in the command @racket["echo Hello --prefix "Output:" "World""].
The @racket[cmd-info] passed to the handler would be @racket[("Hello" (#:prefix) ("Output:") ("World"))].
