#lang racket/base
(require racket/system racket/string racket/format racket/file)
(provide (all-defined-out))
(define-syntax-rule (define-subcommands CMD ...)
  (define-values (CMD ...) (values (symbol->string 'CMD) ...)))

(define command              (make-parameter #f))

(define param-asign          (make-parameter "="))
(define param-list           (make-parameter (lambda (v) (error "No implements param-list" v))))


(define (command-post-process-stdout stdout code subcommand/code? system/cmd)
  (cond
    [(= code 0)   stdout]
    [else         (raise (command-exception (~a system/cmd "\n"  stdout) (current-continuation-marks)))]))

(define command/post-process (make-parameter command-post-process-stdout))

(struct command-exception exn:fail:user ())

(define (command-kw-args-rest kws kw-args subcommand  rest)
  (commmand-run
   (let* ([format-rest (lambda (v)
                         (cond [(or (string? v) (number? v)) (~a (param-asign) "\"" v "\"")]
                               [(boolean? v)    (~a (param-asign) (if v "true" "false"))]
                               [(list?)         ((param-list) v)]
                               [(eq? v '())     ""]
                               [else (error v)]))]
          [formatkv    (lambda (k-v)
                         (let* ([param (car k-v) ]
                                [dash  (if (equal? (string-ref param 0) #\-) "-" "--")]
                                [value (format-rest (cdr k-v))])
                           (~a dash param value )))])
     (append (list subcommand)
             (map formatkv (for/list ([k kws] [v kw-args]) (cons (keyword->string k) v)))
             (map format-rest rest)))))

(define (make-command-wrapper cmd #:post-process [post (command/post-process)] #:param-asign [~param-asign (param-asign)])
  (make-keyword-procedure
   (lambda (kws kw-args subcommand . rest)
    (parameterize ([command     cmd]
                   [param-asign ~param-asign]
                   [command/post-process post])
     (command-kw-args-rest kws kw-args subcommand rest)))))



(define (commmand-run command-cmd-list)
  (let* ([fout          (make-temporary-file)]
         [subcommand    (car command-cmd-list)]
         [cmd           (string-join command-cmd-list)]
         [system/cmd    (format "~a ~a  1> ~a"  (command) cmd  (path->string fout))]
         [code          (system/exit-code system/cmd)]
         [stdout        (string-trim (file->string fout) #:left? #f)]
;;         [stdout/nil?   (equal? "" stdout)]
         [subcommand/code? (lambda (cmd? return) (and (equal? subcommand cmd?) (= return code)))])
    ((command/post-process) stdout code subcommand/code?  system/cmd )
))


