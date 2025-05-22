#lang scribble/manual
@require[@for-label[racket/base racket/contract cmd-wrapper]]
@require[scribble/core scribble/racket]

@title{cmd-wrapper}
@author{javiervivanco}

@defmodule[cmd-wrapper]

Este módulo proporciona una forma de crear envoltorios (wrappers) para comandos de línea de órdenes.
Permite definir un comando base y luego llamarlo con subcomandos, argumentos posicionales y argumentos de palabra clave.

@section{Funciones Principales}

@defproc[(make-command-wrapper [command-name string?] [process-out (-> (listof any/c) exact-integer? string? any/c)]) procedure?]
Crea un procedimiento de envoltorio para el @racket[command-name] dado.
El @racket[command-name] es la orden base a ejecutar (p. ej., @racket["git"], @racket["echo"]).
La función @racket[process-out] es una función de callback que se invoca después de que la orden se ejecuta. Recibe tres argumentos:
@itemlist[
  @item{@racket[cmd-info]: Una lista que contiene el subcomando (si lo hay), una lista de palabras clave, una lista de valores de palabras clave y una lista de argumentos restantes pasados al envoltorio.}
  @item{@racket[exit-code]: El código de salida de la orden ejecutada.}
  @item{@racket[stdout-result]: Una cadena con la salida estándar de la orden.}
]
El procedimiento devuelto por @racket[make-command-wrapper] es un procedimiento de palabra clave. Acepta:
@itemlist[
  @item{Argumentos de palabra clave (p. ej., @racket[#:name "value"]). Estos se transforman en @racket["--name value"] en la línea de órdenes.}
  @item{Un subcomando opcional (como una cadena o símbolo, p. ej., @racket['status] o @racket["status"]).}
  @item{Argumentos posicionales restantes (p. ej., @racket["arg1"] @racket["arg2"]).}
]
La orden se construye concatenando @racket[command-name], el subcomando (si se proporciona), los argumentos de palabra clave formateados y los argumentos restantes formateados.
Luego se ejecuta usando @racket[do-system] (que internamente usa @racket["/bin/sh -c"]).

@bold{Ejemplo de Uso:}
@racketblock[
(define (my-processor cmd-info exit-code stdout)
  (printf "Command Info: ~s~n" cmd-info)
  (printf "Exit Code: ~s~n" exit-code)
  (printf "Stdout: ~s~n" stdout)
  stdout)

(define echo (make-command-wrapper "echo" my-processor))

(echo #:prefix "Output:" "Hello" "World")
;; Esto ejecutaría algo como: echo --prefix "Output:" "Hello" "World"
;; Y luego llamaría a my-processor con los detalles.
]


@defproc[(-- [args (listof any/c)]) bytes?]
Una función de ayuda para formatear argumentos individuales o pares clave-valor en cadenas de bytes adecuadas para argumentos de línea de órdenes.
Principalmente para uso interno o para construir partes de órdenes manualmente si es necesario.
Convierte símbolos y cadenas en formatos como @racket["--option value"] o @racket["-f value"].
Los valores se formatean usando @code{arg->cmd}.

@section{Formateo de Argumentos con @code{arg->cmd}}

La función (no exportada) @code{arg->cmd} es utilizada internamente por @code{build-args} (que a su vez es usada por @racket[make-command-wrapper]) y por la función de ayuda @racket[--] para convertir valores de Racket en representaciones de cadena adecuadas para la línea de órdenes. Su comportamiento es el siguiente:
@itemlist[
  @item{@bold{Cadenas y Números:} Se encierran entre comillas dobles (p. ej., @racket["hello"] se convierte en @racket["\"hello\""], @racket[123] se convierte en @racket["\"123\""]).}
  @item{@bold{Booleanos:} @racket[#t] se convierte en @racket["true"], @racket[#f] se convierte en @racket["false"].}
  @item{@bold{Listas:} Se procesan recursivamente sus elementos, uniéndolos con espacios. Una lista vacía se convierte en un solo espacio en blanco (@racket[" "]). (p. ej., @racket['("a" "b")] se convierte en @racket["\"a\" \"b\""]).}
  @item{@bold{Bytes y Rutas (Paths):} Se convierten directamente a su representación de cadena (p. ej., @racket[#"bytes"] se convierte en @racket["bytes"], @racket[(build-path "a" "b")] se convierte en @racket["a/b"] o @racket["a\\b"] dependiendo del SO).}
  @item{@bold{Null y Void:} Se convierten en un solo espacio en blanco (@racket[" "]).}
  @item{@bold{Otros Tipos:} Provocan un error.}
]
Este formateo asegura que los argumentos se pasen a las órdenes del sistema de una manera que generalmente es segura y predecible.

@section{Ejemplo Complejo: Envoltorio de Git}

A continuación, se muestra cómo se puede crear y usar un envoltorio para la orden @racket[git]:

@racketblock[
(require cmd-wrapper)

;; Un manejador de salida simple para git
(define (git-result-handler cmd-info exit-code stdout)
  (printf "== Git Command Executed ==~n")
  (printf "Cmd Info: ~s~n" cmd-info)
  (printf "Exit Code: ~s~n" exit-code)
  (printf "STDOUT:~n%s~n" stdout)
  (if (zero? exit-code)
      (string-split stdout "
") ; Devuelve líneas de salida como una lista en caso de éxito
      #f)) ; Devuelve #f en caso de error

(define git (make-command-wrapper "git" git-result-handler))

;; Obtener el estado actual de git
(git 'status)

;; Obtener el estado corto de git (git status --short)
(git #:short #t 'status) ;; También (git 'status #:short #t)

;; Ver las últimas 2 confirmaciones, en una línea
(git 'log #:max-count 2 #:oneline #t)

;; Intentar crear una nueva rama (esto es solo para demostración,
;; la orden real podría necesitar manejo de errores más específico si la rama ya existe)
(git 'checkout #:b "my-new-feature")
(git 'branch)
]

Este ejemplo ilustra cómo @racket[make-command-wrapper] facilita la interacción con utilidades de línea de órdenes complejas como @racket[git], manejando la construcción de la cadena de la orden y permitiendo un procesamiento personalizado de la salida.
La flexibilidad en el orden de los subcomandos y los argumentos de palabra clave (como se ve en @racket[(git #:short #t 'status)]) es una característica del procedimiento de palabra clave generado.
