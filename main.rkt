#lang racket/base
(require racket/system racket/string racket/format racket/file racket/match racket/port racket/private/port racket/private/streams racket/list)
(provide make-command-wrapper -- arg->cmd)

(define COMMAND_DEBUG (make-parameter #t))

(define (call-with-pwd f)
  (parameterize ([current-environment-variables
                  (environment-variables-copy
                   (current-environment-variables))])
    (putenv "PWD" (path->string (current-directory)))
    (f)))

(define (path-or-ok-string? s)
  (or (path-string? s) (equal? "" s)))

(define (check-args who args)
  (cond
    [(null? args) (void)]
    [(eq? (car args) 'exact)
     (when (null? (cdr args))
       (raise-mismatch-error
        who
        "expected a single string argument after: "
        (car args)))
     (unless (and (>= 2 (length args))
                  (string? (cadr args))
                  (path-or-ok-string? (cadr args)))
       (raise-mismatch-error who
                             "expected a single string argument after 'exact, given: "
                             (cadr args)))
     (when (pair? (cddr args))
       (raise-mismatch-error
        who
        "expected a single string argument after 'exact, given additional argument: "
        (caddr args)))]
    [else
     (for ([s (in-list args)])
       (unless (or (path-or-ok-string? s) (bytes-no-nuls? s))
         (raise-argument-error who "(or/c path-string? bytes-no-nuls?)" s)))])
  args)

(define (do-system  . args)
  (define who 'do-system*/exit-code)
  (let ([cout (current-output-port)]
        [cin (current-input-port)]
        [cerr (current-error-port)]
        [it-ready (make-semaphore)])
    (let-values ([(subp out in err)
                  (call-with-pwd
                   (lambda ()
                     (apply subprocess
                            #f
                            (if-stream-in who cin)
                            (if-stream-out who cerr #t)
                            "/bin/sh"
                            (check-args who (append '("-c") args)))))])
      (define stdoutstr #f)
      (let ([ot (streamify-out cout out)]
            [it (streamify-in cin in (lambda (ok?)
                                       (if ok?
                                           (semaphore-post it-ready)
                                           (semaphore-wait it-ready))))]
            [et (streamify-out cerr err)])
        (subprocess-wait subp)
        (when it
          (semaphore-wait it-ready)
          (break-thread it)
          (thread-wait it))
        (when (thread? ot) (thread-wait ot))
        (when (thread? et) (thread-wait et))
        (when err (close-input-port err))
        (when out (set! stdoutstr (port->string out))
          (close-input-port out))
        (when in (close-output-port in)))
      (values
       (subprocess-status subp)
       stdoutstr
       ))))

(define (log-debug msg)
  (when (COMMAND_DEBUG) (displayln (format "\n~a" msg))))

(define (build-args command kws kw-args rest)
  (append (if command (list command) '())
          (for/list ([k kws]
                      [v kw-args])
            (if (keyword? k) (format "--~a ~a" (keyword->string k) (arg->cmd v))
                             (error 'build-args "Expected a keyword, got ~a" k)))
          (map arg->cmd rest)))

(define (make-command-wrapper command-name process-out #:args [args '()])
  (let
      ([COMMAND_BIN_PATH (if (string? command-name) command-name (error 'command "not found"))])
    (unless COMMAND_BIN_PATH (error 'command "not found ~a command-name" command-name))
    (make-keyword-procedure
     (lambda (kws kw-args subcommand . rest)
       (define cmd-args (build-args subcommand kws kw-args rest))
       (define cmd-str (~a COMMAND_BIN_PATH " " (string-join cmd-args " ")))
       (log-debug (format "Executing command via do-system: ~s" cmd-str))
       (define-values (exit-code stdout-result)
         (do-system cmd-str))
       (log-debug (format "do-system results: exit-code=~s, stdout-result=~s" exit-code stdout-result))
       (process-out (list subcommand kws kw-args rest) exit-code stdout-result)))))

(define  (arg->cmd v)
  (cond [(or (string? v) (number? v)) (format "\"~a\"" v)]
        [(list? v )                   (if (null? v) " " (string-join (map arg->cmd v) " "))]
        [(boolean? v)                 (if v "true" "false")]
        [(or
          (bytes? v)
          (path?  v))          (format "~a" v)]
        [(or
          (null? v)
          (void? v ))                  " "]
        [else                       (println v)  (error 'arg->cmd "Invalid argument type: ~a" v)]))

(define (-- . args)
  (match args ; Return byte string directly
    [(list (list x v))   (string->bytes/utf-8 (format "--~a ~a" x (arg->cmd v)))]
    [(list (cons x '())) (string->bytes/utf-8 (format "--~a" x))]
    [(list (cons x v))   (string->bytes/utf-8 (format "--~a=~a" x (arg->cmd v)))]
    [(list (list x))     (string->bytes/utf-8 (format "--~a" x))]
    [(list s v) (let ([s-str (if (symbol? s) (symbol->string s) s)])
                  (string->bytes/utf-8 ; Ensure this branch also returns bytes
                   (if (and (symbol? s) (> (string-length (symbol->string s)) 1))
                       (format "--~a ~a" s-str (arg->cmd v))
                       (format "-~a ~a" s-str (arg->cmd v)))))]
    [(list s)   (let ([s-str (if (symbol? s) (symbol->string s) s)])
                  (string->bytes/utf-8 ; Ensure this branch also returns bytes
                   (if (and (symbol? s) (> (string-length (symbol->string s)) 1))
                       (format "--~a" s-str)
                       (format "-~a" s-str))))]))

(module+ test
  (require rackunit racket/file)
  (COMMAND_DEBUG #t)
  (test-case "Testing arg->cmd formatting"
    (check-equal? (arg->cmd "hello") "\"hello\"" "String formatting")
    (check-equal? (arg->cmd 123) "\"123\"" "Number formatting")
    (check-equal? (arg->cmd #t) "true" "Boolean true formatting")
    (check-equal? (arg->cmd #f) "false" "Boolean false formatting")
    (check-equal? (arg->cmd '("a" "b")) "\"a\" \"b\"" "List of strings formatting")
    (check-equal? (arg->cmd #"bytes") "bytes" "Bytes formatting")
    (check-equal? (arg->cmd (build-path "a" "b")) (path->string (build-path "a" "b")) "Path formatting")
    (check-equal? (arg->cmd '()) " " "Empty list formatting")
    (check-equal? (arg->cmd (void)) " " "Void formatting"))

  (test-case "Testing -- argument helper"
    (check-equal? (-- 'test-arg "value") #"--test-arg \"value\"" "Long option with value")
    (check-equal? (-- 'test-arg) #"--test-arg" "Long option flag")
    (check-equal? (-- '(test-arg . "value")) #"--test-arg=\"value\"" "Long option with value (cons)")
    (check-equal? (-- 't "value") #"-t \"value\"" "Short option with value, symbol treated as short")
    (check-equal? (-- "t" "value") #"-t \"value\"" "Short option with value, string")
    (check-equal? (-- 't) #"-t" "Short option flag, symbol treated as short")
    (check-equal? (-- "t") #"-t" "Short option flag, string"))

  (define (test-processor-mkw expected-cmd-info expected-exit-code expected-stdout-contains)
    (lambda (cmd-info exit-code stdout-result)
      (log-debug (format "test-processor-mkw received: cmd-info=~s, exit-code=~s, stdout=~s" cmd-info exit-code stdout-result))
      (match cmd-info
        [(list sub kws kw-args rest)
         (check-equal? sub (car expected-cmd-info) "Subcommand in process-out")
         (check-equal? kws (cadr expected-cmd-info) "KWs in process-out")
         (check-equal? kw-args (caddr expected-cmd-info) "KW-Args in process-out")
         (check-equal? rest (cadddr expected-cmd-info) "Rest args in process-out")])
      (check-equal? exit-code expected-exit-code "Exit code in process-out")
      (check-pred string? stdout-result "Stdout should be a string from do-system")
      (when (string? stdout-result)
        (check-true (string-contains? stdout-result expected-stdout-contains)
                    (format "Stdout should contain '~a', got '~a'" expected-stdout-contains stdout-result)))
      (values cmd-info exit-code stdout-result)))

  (test-case "Testing make-command-wrapper with user's version (echo command)"
    (define echo-cmd
      (make-command-wrapper "echo"
                            (test-processor-mkw
                             '("hello" (#:name) ("world") ("extra"))
                             0
                             "hello --name world extra")))
    (let-values ([(received-info exit-c actual-out) (echo-cmd #:name "world" "hello" "extra")])
      (check-equal? exit-c 0 "Echo command exit code should be 0")
      (check-pred string? actual-out "Echo command output should be a string")
      (when (string? actual-out)
        (check-true (string-contains? actual-out "hello --name world extra")
                    (format "Expected echo output to contain 'hello --name world extra', got: ~s" actual-out)))))

  (test-case "Testing with real command (ls) in a temporary directory"
    (define temp-dir #f)
    (define temp-file-1-name "testfile1.txt")
    (define temp-file-2-name "testfile2.txt")

    (dynamic-wind
     (lambda () ; Before thunk
       (set! temp-dir (make-temporary-file "test-cmd-wrapper-dir-~a" 'directory))
       (log-debug (format "Created temp dir: ~a for ls test" temp-dir))
       (when temp-dir
         (let ([temp-file-1-path (build-path temp-dir temp-file-1-name)]
               [temp-file-2-path (build-path temp-dir temp-file-2-name)])
           (with-output-to-file temp-file-1-path #:exists 'replace (lambda () (display "content1")))
           (with-output-to-file temp-file-2-path #:exists 'replace (lambda () (display "content2"))))))
     (lambda () ; Body thunk
       (define (ls-test-results-handler cmd-info exit-code stdout-result)
         (values cmd-info exit-code stdout-result))
       (define ls-cmd (make-command-wrapper "ls" ls-test-results-handler))

       (if temp-dir
           (begin
             (log-debug (format "Running wrapped ls command for dir: ~a" (path->string temp-dir)))
             (let-values ([(received-cmd-info exit-code output-string) (ls-cmd (path->string temp-dir))])
               (log-debug (format "ls command info received by handler: ~s" received-cmd-info))
               (log-debug (format "ls exit code: ~a" exit-code))
               (when output-string (log-debug (format "ls stdout (string): ~s" output-string)))
               (check-equal? exit-code 0 "ls command should succeed")
               (check-pred string? output-string "stdout should be a string")
               (if (string? output-string)
                   (begin
                     (log-debug (format "ls stdout (string to check): ~a" output-string))
                     (check-true (string-contains? output-string temp-file-1-name)
                                 (format "Output should contain ~s. Output: ~s" temp-file-1-name output-string))
                     (check-true (string-contains? output-string temp-file-2-name)
                                 (format "Output should contain ~s. Output: ~s" temp-file-2-name output-string)))
                   (check-false #t (format "Expected string output from ls, but got: ~s" output-string)))))
           (begin
             (log-debug "Skipping ls test because temp-dir was not created.")
             (void))))
     (lambda () ; After thunk
       (when (and temp-dir (directory-exists? temp-dir))
         (log-debug (format "Deleting temp dir: ~a after ls test" temp-dir))
         (delete-directory/files temp-dir)
         (set! temp-dir #f)))))
  ) ; Close module+ test
