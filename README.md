# cmd-wrapper

`cmd-wrapper` is a Racket library designed to simplify the creation and management of command-line executable wrappers. It provides utilities to build command strings, execute them, and process their output.

## Features

- Easy creation of command wrappers from a base command name.
- Flexible argument formatting, including support for strings, numbers, booleans, lists, paths, and byte strings.
- Keyword-based argument construction.
- Captures exit codes and standard output from executed commands.

## Installation

To use `cmd-wrapper` in your project, you can install it as a Racket package. If this package were published to the official Racket package server, you would typically install it using:

```shell
raco pkg install cmd-wrapper
```

For local development, you can link the package:

```shell
cd /path/to/command-wrapper
raco pkg install --link .
```

## Usage

Here's a basic example of how to use `make-command-wrapper`:

```racket
#lang racket/base
(require cmd-wrapper)

; Define a function to process the output
(define (my-output-processor command-info exit-code stdout-result)
  (printf "Command: ~s~n" command-info)
  (printf "Exit Code: ~a~n" exit-code)
  (printf "Output:\n~a\n" stdout-result))

; Create a wrapper for the 'ls' command
(define ls (make-command-wrapper "ls" my-output-processor))

; Run the wrapper
(ls #:long #t #:all #t "/tmp")
; This might execute something like: ls --long --all "/tmp"

; The '--' helper can be used to format arguments:
(define formatted-args (-- '(\"l\" \"/var/log\")))
; formatted-args would be something like #"-l \"/var/log\""
```

## Documentation

Detailed documentation can be generated from the Scribble files located in the `scribblings` directory.

To build the documentation:

```shell
make docs
```

This will generate HTML documentation in the `doc` directory. You can open `doc/cmd-wrapper.html` in your web browser.

## Building from Source

1. Clone the repository:
   ```shell
   git clone <repository-url>
   cd command-wrapper
   ```
2. Install dependencies (if any beyond base Racket, though this example primarily uses base):
   ```shell
   raco pkg install --auto --name cmd-wrapper
   ```
3. Compile the module and build documentation:
   ```shell
   raco setup cmd-wrapper
   ```
   or use the Makefile target:
   ```shell
   make docs
   ```

## Running Tests

To run the tests for this package (assuming tests are defined and configured):

```shell
raco test -p cmd-wrapper
```

## License

This project is licensed under the terms of the Apache-2.0 license or the MIT license. See the `LICENSE-APACHE` and `LICENSE-MIT` files for details.
