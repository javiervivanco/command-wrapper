#lang racket/base
(require racket/system racket/string racket/format racket/file racket/match racket/port racket/private/port racket/private/streams)
(provide (all-defined-out))




(define COMMAND_DEBUG (make-parameter #t))

(define (call-with-pwd f)
  (parameterize ([current-environment-variables
                  (environment-variables-copy
                   (current-environment-variables))])
    (putenv "PWD" (path->string (current-directory)))
    (f)))


(define-syntax-rule (define-subcommands CMD ...)
  (define-values (CMD ...) (values (symbol->string 'CMD) ...)))

(define (path-or-ok-string? s)
  ;; use `path-string?' t check for nul characters in a string,
  ;; but allow the empty string (which is not an ok path), too:
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
          ;; stop piping output to subprocess
          (semaphore-wait it-ready)
          (break-thread it)
          (thread-wait it))
        ;; wait for other pipes to run dry:
        
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
          (for/list  ([k kws]
                      [v kw-args])
            (-- (keyword->string k) v))
          (map arg->cmd rest)))

(define (make-command-wrapper command-name std-out )
  (let
      ([COMMAND_BIN_PATH (if (string? command-name) command-name (error 'command "not found"))])
    (unless COMMAND_BIN_PATH (error 'command "not found ~a command-name" command-name))
    (make-keyword-procedure
     (lambda (kws kw-args subcommand . rest)
       (define cmd-args (build-args subcommand kws kw-args rest))
       
       (define-values (exit-code stdout-result)
         (do-system  (~a COMMAND_BIN_PATH " " (string-join cmd-args  " "))))
       (cond
         [(= exit-code 0)      (std-out (list subcommand kws kw-args rest) stdout-result)]
         [else                 
          (error 'command "~a failed: ~a" command-name subcommand )
          (current-continuation-marks)])))))



(define  (arg->cmd v)
  (cond [(or (string? v) (number? v)) (format "\"~a\"" v)]
        [(list? v )                   (string-join (map arg->cmd v) " ") ]
        [(boolean? v)                 (if v "true" "false")]
        [(or
          (bytes? v)
          (path?  v))          (format "~a" v)]
        [(or
          (eq? v '())
          (void? v ))                  " "]
        [else                       (println v)  (error 'ar-opt "args ~a" v)]))



(define (-- . args)
  (string->bytes/utf-8
   (match args
     [(list (list x v))   (format "--~a ~a" x (arg->cmd v))]
     [(list (cons x '())) (format "--~a" x )]
     [(list (cons x v))   (format "--~a=~a" x (arg->cmd v))]
     [(list (list x))     (format "--~a" x)]
     [(list  x v)         (format "-~a ~a" x (arg->cmd v))]
     [(list x)            (format "-~a" x)])))
