;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2019, 2023 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (test-store-deduplication)
  #:use-module (guix tests)
  #:use-module (guix store)
  #:use-module (guix store roots)
  #:use-module ((guix utils) #:select (call-with-temporary-directory))
  #:use-module ((guix build utils) #:select (delete-file-recursively))
  #:use-module ((guix config) #:select (%state-directory))
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64))

(define %store #f)

(test-begin "store-roots")

(test-equal "gc-roots, initial"
  (list (string-append %state-directory "/profiles"))
  (begin
    ;; 'gc-roots' should gracefully handle lack of that directory.
    (delete-file-recursively (string-append %state-directory "/profiles"))
    (gc-roots)))

;; The 'open-connection' call below gets guix-daemon to create
;; %STATE-DIRECTORY/profiles.
(set! %store (open-connection))

(test-assert "gc-roots, regular root"
  (let* ((item (add-text-to-store %store "something"
                                  (random-text)))
         (root (string-append %gc-roots-directory "/test-gc-root")))
    (symlink item root)
    (let ((result (member root (gc-roots))))
      (delete-file root)
      result)))

(test-assert "gc-roots, indirect root"
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((item (add-text-to-store %store "something"
                                     (random-text)))
            (root (string-append directory "/gc-root")))
       (symlink item root)
       (add-indirect-root %store root)
       (let ((result (member root (gc-roots))))
         (delete-file root)
         result)))))

(test-end "store-roots")
