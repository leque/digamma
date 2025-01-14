;;; Copyright (c) 2004-2019 Yoshikatsu Fujita / LittleWing Company Limited.
;;; See LICENSE file for terms and conditions of use.

(define-library
  (scheme char)
  (import (core) (core unicode-assistants))
  (export char-alphabetic?
          char-ci<?
          char-ci>=?
          char-downcase
          char-lower-case?
          char-upcase
          char-whitespace?
          string-ci<=?
          string-ci=?
          string-ci>?
          string-foldcase
          char-ci<=?
          char-ci=?
          char-ci>?
          char-foldcase
          char-numeric?
          char-upper-case?
          digit-value
          string-ci<?
          string-ci>=?
          string-downcase
          string-upcase)
) ;[end]
