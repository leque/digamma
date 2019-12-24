;;; Copyright (c) 2004-2019 Yoshikatsu Fujita / LittleWing Company Limited.
;;; See LICENSE file for terms and conditions of use.

(define expand-define-library
  (lambda (form env)

    (define permute-env
      (lambda (ht)
        (let loop ((lst (core-hashtable->alist ht)) (bounds '()) (unbounds '()))
          (cond ((null? lst) (append bounds unbounds)) ((unbound? (cdar lst)) (loop (cdr lst) bounds (cons (car lst) unbounds))) (else (loop (cdr lst) (cons (car lst) bounds) unbounds))))))

    (destructuring-match form
      ((_ library-name clauses ...)
       (let ((library-id (library-name->id form library-name)) (library-version (library-name->version form library-name)))
         (and library-version (core-hashtable-set! (scheme-library-versions) library-id library-version))
         (parameterize ((current-include-files (make-core-hashtable)))
           (let ((ht-immutables (make-core-hashtable)) (ht-imports (make-core-hashtable)) (ht-publics (make-core-hashtable)))
             (let ((coreform
                     (let loop ((clauses clauses) (exports '()) (imports '()) (depends '()) (commands '()))
                       (if (null? clauses)
                           (begin
                             (for-each (lambda (a)
                                         (and (core-hashtable-ref ht-publics (cdr a) #f) (syntax-violation 'define-library "duplicate export identifiers" (abbreviated-take-form form 4 8) (cdr a)))
                                         (core-hashtable-set! ht-publics (cdr a) #t)
                                         (core-hashtable-set! ht-immutables (car a) #t))
                                       exports)
                             (for-each (lambda (a)
                                         (core-hashtable-set! ht-immutables (car a) #t)
                                         (cond ((core-hashtable-ref ht-imports (car a) #f)
                                                =>
                                                (lambda (deno) (or (eq? deno (cdr a)) (syntax-violation 'define-library "duplicate import identifiers" (abbreviated-take-form form 4 8) (car a)))))
                                               (else (core-hashtable-set! ht-imports (car a) (cdr a)))))
                                       imports)
                             (let ((ht-env (make-shield-id-table commands)) (ht-libenv (make-core-hashtable)))
                               (for-each (lambda (a)
                                           (core-hashtable-set! ht-env (car a) (cdr a))
                                           (core-hashtable-set! ht-libenv (car a) (cdr a)))
                                         (core-hashtable->alist ht-imports))
                               (parameterize ((current-immutable-identifiers ht-immutables))
                                 (expand-define-library-body
                                   form
                                   library-id
                                   library-version
                                   commands
                                   exports
                                   imports
                                   depends
                                   (extend-env private-primitives-environment (permute-env ht-env))
                                   (permute-env ht-libenv)))))
                           (destructuring-match clauses
                             ((('export export-spec ...) more ...)
                              (loop more (append exports (parse-exports form export-spec)) imports depends commands))
                             ((('import import-spec ...) more ...)
                              (loop more exports (append imports (parse-imports form import-spec)) (append depends (parse-depends form import-spec)) commands))
                             ((('begin body ...) more ...)
                              (loop more exports imports depends (append commands body)))
                             (_
                              (syntax-violation 'define-library "malformed library spec" (abbreviated-take-form form 4 8) (car clauses))))))))
               (or (= (core-hashtable-size (current-include-files)) 0) (core-hashtable-set! library-include-dependencies library-id (current-include-files)))
               coreform)))))
      (_ (syntax-violation 'define-library "expected library name and specs" (abbreviated-take-form form 4 8))))))

(define expand-define-library-body
  (lambda (form library-id library-version body exports imports depends env libenv)

    (define initial-libenv #f)

    (define internal-definition?
      (lambda (lst)
        (and (pair? lst)
             (pair? (car lst))
             (symbol? (caar lst))
             (let ((deno (env-lookup env (caar lst))))
               (or (macro? deno)
                   (eq? denote-define deno)
                   (eq? denote-define-syntax deno)
                   (eq? denote-let-syntax deno)
                   (eq? denote-letrec-syntax deno))))))

    (define macro-defs '())

    (define extend-env!
      (lambda (datum1 datum2)
        (and (macro? datum2)
             (set! macro-defs (acons datum1 datum2 macro-defs)))
        (set! env (extend-env (list (cons datum1 datum2)) env))
        (for-each (lambda (a) (set-cdr! (cddr a) env)) macro-defs)))

    (define extend-libenv!
      (lambda (datum1 datum2)
        (set! libenv (extend-env (list (cons datum1 datum2)) libenv))
        (current-template-environment libenv)))

    (define rewrite-body
      (lambda (body defs macros renames)

        (define rewrite-env
          (lambda (env)
            (let loop ((lst (reverse env)) (acc '()))
              (cond ((null? lst) acc)
                    ((uninterned-symbol? (caar lst))
                     (if (assq (cdar lst) defs)
                         (loop (cdr lst) (cons (cons (caar lst) (cddr (assq (cdar lst) libenv))) acc))
                         (loop (cdr lst) (cons (car lst) acc))))
                    ((assq (caar lst) (cdr lst))
                     (loop (cdr lst) acc))
                    (else
                     (loop (cdr lst) (cons (car lst) acc)))))))

        (define make-rule-macro
          (lambda (type id spec shared-env)
            `(.set-top-level-macro! ',type ',id ',spec ,shared-env)))

        (define make-var-macro
          (lambda (type id spec shared-env)
            `(.set-top-level-macro! ',type ',id (.transformer-thunk ,spec) ,shared-env)))

        (define make-proc-macro
          (lambda (type id spec shared-env)
            (cond ((and (pair? spec) (eq? (car spec) 'lambda))
                   `(.set-top-level-macro! ',type ',id (.transformer-thunk ,spec) ,shared-env))
                  (else
                   (let ((x (generate-temporary-symbol)))
                     `(.set-top-level-macro! ',type
                                             ',id
                                             (let ((proc #f))
                                               (lambda (,x)
                                                 (if proc
                                                     (proc ,x)
                                                     (begin
                                                       (set! proc (.transformer-thunk ,spec))
                                                       (proc ,x)))))
                                             ,shared-env))))))

        (check-duplicate-definition 'define-library defs macros renames)
        (let ((env (rewrite-env env)))
          (let ((rewrited-body (expand-each body env)))
            (let* ((rewrited-depends
                    (map (lambda (dep) `(.require-scheme-library ',dep)) depends))
                   (rewrited-defs
                    (map (lambda (def)
                           (parameterize ((current-top-level-exterior (car def)))
                             (let ((lhs (cdr (assq (car def) renames)))
                                   (rhs (expand-form (cadr def) env)))
                               (set-closure-comment! rhs lhs)
                               `(define ,lhs ,rhs))))
                         defs))
                   (rewrited-macros
                    (cond ((null? macros) '())
                          (else
                           (let ((ht-visibles (make-core-hashtable)))
                             (for-each (lambda (e) (core-hashtable-set! ht-visibles (car e) #t)) macros) ; 090526
                             (let loop ((lst (map caddr macros)))
                               (cond ((pair? lst) (loop (car lst)) (loop (cdr lst)))
                                     ((symbol? lst) (core-hashtable-set! ht-visibles lst #t))
                                     ((vector? lst) (loop (vector->list lst)))))
                             (for-each (lambda (b)
                                         (or (assq (car b) libenv)
                                             (let ((deno (env-lookup env (car b))))
                                               (if (and (symbol? deno) (not (eq? deno (car b))))
                                                   (extend-libenv! (car b) (make-import deno))
                                                   (or (uninterned-symbol? (car b))
                                                       (core-primitive-name? (car b))
                                                       (extend-libenv! (car b) (make-unbound)))))))
                                       (core-hashtable->alist ht-visibles))
                             (let ((shared-env (generate-temporary-symbol)))
                               `((let ((,shared-env
                                         ',(let ((ht (make-core-hashtable)))
                                             (for-each (lambda (a)
                                                         (and (core-hashtable-contains? ht-visibles (car a))
                                                              (core-hashtable-set! ht (car a) (cdr a))))
                                                       (reverse libenv))
                                             (core-hashtable->alist ht))))
                                   ,@(map (lambda (e)
                                            (let ((id (cdr (assq (car e) renames)))
                                                  (type (cadr e))
                                                  (spec (caddr e)))
                                              (case type
                                                ((template)
                                                 (make-rule-macro 'syntax id spec shared-env))
                                                ((procedure)
                                                 (make-proc-macro 'syntax id spec shared-env))
                                                ((variable)
                                                 (make-var-macro 'variable id spec shared-env))
                                                (else
                                                 (scheme-error "internal error in rewrite body: bad macro spec ~s" e)))))
                                          macros))))))))
                   (rewrited-exports
                    `(.intern-scheme-library
                      ',library-id
                      ',library-version
                      ',(begin
                          (map (lambda (e)
                                 (cons (cdr e)
                                       (cond ((assq (car e) renames) => (lambda (a) (make-import (cdr a))))
                                             ((assq (car e) imports) => cdr)
                                             (else
                                              (current-macro-expression #f)
                                              (syntax-violation 'define-library
                                                                (format "attempt to export unbound identifier ~u" (car e))
                                                                (caddr form))))))
                               exports)))))
              (let ((vars (map cadr rewrited-defs))
                    (assignments (map caddr rewrited-defs)))
                (cond ((check-rec*-contract-violation vars assignments)
                       => (lambda (var)
                            (let ((id (any1 (lambda (a) (and (eq? (cdr a) (car var)) (car a))) renames)))
                              (current-macro-expression #f)
                              (syntax-violation #f
                                                (format "attempt to reference uninitialized variable ~u" id)
                                                (any1 (lambda (e)
                                                        (and (check-rec-contract-violation (list id) e)
                                                             (annotate `(define ,@e) e)))
                                                      defs)))))))
              (annotate `(begin
                           ,@rewrited-depends
                           ,@rewrited-defs
                           ,@rewrited-body
                           ,@rewrited-macros
                           ,rewrited-exports)
                        form))))))

    (define ht-imported-immutables (make-core-hashtable))

    (current-template-environment libenv)
    (for-each (lambda (b) (core-hashtable-set! ht-imported-immutables (car b) #t)) imports)
    (let loop ((body (flatten-begin body env)) (defs '()) (macros '()) (renames '()))
      (cond ((and (pair? body) (pair? (car body)) (symbol? (caar body)))
             (let ((deno (env-lookup env (caar body))))
               (cond ((eq? denote-begin deno)
                      (loop (flatten-begin body env) defs macros renames))
                     ((eq? denote-define-syntax deno)
                      (destructuring-match body
                        (((_ (? symbol? org) clause) more ...)
                         (begin
                           (and (core-hashtable-contains? ht-imported-immutables org)
                                (syntax-violation 'define-syntax "attempt to modify immutable binding" (car body)))
                           (let-values (((code . expr)
                                         (parameterize ((current-template-environment initial-libenv))
                                           (compile-macro (car body) clause env))))
                             (let ((new (generate-global-id library-id org)))
                               (extend-libenv! org (make-import new))
                               (cond ((procedure? code)
                                      (extend-env! org (make-macro code env))
                                      (loop more defs (cons (list org 'procedure (car expr)) macros) (acons org new renames)))
                                     ((macro-variable? code)
                                      (extend-env! org (make-macro-variable (cadr code) env))
                                      (loop more defs (cons (list org 'variable (car expr)) macros) (acons org new renames)))
                                     (else
                                      (extend-env! org (make-macro code env))
                                      (loop more defs (cons (list org 'template code) macros) (acons org new renames))))))))
                        (_
                         (syntax-violation 'define-syntax "expected symbol and single expression" (car body)))))
                     ((eq? denote-define deno)
                      (let ((def (annotate (cdr (desugar-define (car body))) (car body))))
                        (and (core-hashtable-contains? ht-imported-immutables (car def))
                             (syntax-violation 'define "attempt to modify immutable binding" (car body)))
                        (let ((org (car def))
                              (new (generate-global-id library-id (car def))))
                          (extend-env! org new)
                          (extend-libenv! org (make-import new))
                          (loop (cdr body) (cons def defs) macros (acons org new renames)))))
                     ((or (macro? deno)
                          (eq? denote-let-syntax deno)
                          (eq? denote-letrec-syntax deno))
                      (let-values (((expr new) (expand-initial-forms (car body) env)))
                        (set! env new)
                        (let ((maybe-def (flatten-begin (list expr) env)))
                          (cond ((null? maybe-def)
                                 (loop (cdr body) defs macros renames))
                                ((internal-definition? maybe-def)
                                 (loop (append maybe-def (cdr body)) defs macros renames))
                                (else
                                 (rewrite-body body (reverse defs) (reverse macros) renames))))))
                     (else
                      (rewrite-body body (reverse defs) (reverse macros) renames)))))
            (else
             (rewrite-body body (reverse defs) (reverse macros) renames))))))