;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016 Ludovic Courtès <ludo@gnu.org>
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

(define-module (test-system)
  #:use-module (gnu)
  #:use-module (guix store)
  #:use-module (gnu services herd)
  #:use-module (gnu services shepherd)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64))

;; Test the (gnu system) module.

(define %root-fs
  (file-system
    (device "my-root")
    (title 'label)
    (mount-point "/")
    (type "ext4")))

(define %os
  (operating-system
    (host-name "komputilo")
    (timezone "Europe/Berlin")
    (locale "en_US.utf8")
    (bootloader (grub-configuration (device "/dev/sdX")))
    (file-systems (cons %root-fs %base-file-systems))

    (users %base-user-accounts)))

(define %luks-device
  (mapped-device
   (source "/dev/foo") (target "my-luks-device")
   (type luks-device-mapping)))

(define %os-with-mapped-device
  (operating-system
    (host-name "komputilo")
    (timezone "Europe/Berlin")
    (locale "en_US.utf8")
    (bootloader (grub-configuration (device "/dev/sdX")))
    (mapped-devices (list %luks-device))
    (file-systems (cons (file-system
                          (inherit %root-fs)
                          (dependencies (list %luks-device)))
                        %base-file-systems))
    (users %base-user-accounts)))

(define live-service
  (@@ (gnu services herd) live-service))

(define service-upgrade
  (@@ (guix scripts system) service-upgrade))

(test-begin "system")

(test-assert "operating-system-store-file-system"
  ;; %BASE-FILE-SYSTEMS defines a bind-mount for /gnu/store, but this
  ;; shouldn't be a problem.
  (eq? %root-fs
       (operating-system-store-file-system %os)))

(test-assert "operating-system-store-file-system, prefix"
  (let* ((gnu (file-system
                (device "foobar")
                (mount-point (dirname (%store-prefix)))
                (type "ext5")))
         (os  (operating-system
                (inherit %os)
                (file-systems (cons* gnu %root-fs
                                     %base-file-systems)))))
    (eq? gnu (operating-system-store-file-system os))))

(test-assert "operating-system-store-file-system, store"
  (let* ((gnu (file-system
                (device "foobar")
                (mount-point (%store-prefix))
                (type "ext5")))
         (os  (operating-system
                (inherit %os)
                (file-systems (cons* gnu %root-fs
                                     %base-file-systems)))))
    (eq? gnu (operating-system-store-file-system os))))

(test-equal "operating-system-user-mapped-devices"
  '()
  (operating-system-user-mapped-devices %os-with-mapped-device))

(test-equal "operating-system-boot-mapped-devices"
  (list %luks-device)
  (operating-system-boot-mapped-devices %os-with-mapped-device))

(test-equal "operating-system-boot-mapped-devices, implicit dependency"
  (list %luks-device)

  ;; Here we expect the implicit dependency between "/" and
  ;; "/dev/mapper/my-luks-device" to be found, in spite of the lack of a
  ;; 'dependencies' field in the root file system.
  (operating-system-boot-mapped-devices
   (operating-system
     (inherit %os-with-mapped-device)
     (file-systems (cons (file-system
                           (device "/dev/mapper/my-luks-device")
                           (title 'device)
                           (mount-point "/")
                           (type "ext4"))
                         %base-file-systems)))))

(test-equal "service-upgrade: nothing to do"
  '(() ())
  (call-with-values
      (lambda ()
        (service-upgrade '() '()))
    list))

(test-equal "service-upgrade: one unchanged, one upgraded, one new"
  '(((bar))                                       ;unload
    ((bar) (baz)))                                ;load
  (call-with-values
      (lambda ()
        ;; Here 'foo' is not upgraded because it is still running, whereas
        ;; 'bar' is upgraded because it is not currently running.  'baz' is
        ;; loaded because it's a new service.
        (service-upgrade (list (live-service '(foo) '() #t)
                               (live-service '(bar) '() #f)
                               (live-service '(root) '() #t)) ;essential!
                         (list (shepherd-service (provision '(foo))
                                                 (start #t))
                               (shepherd-service (provision '(bar))
                                                 (start #t))
                               (shepherd-service (provision '(baz))
                                                 (start #t)))))
    (lambda (unload load)
      (list (map live-service-provision unload)
            (map shepherd-service-provision load)))))

(test-equal "service-upgrade: service depended on is not unloaded"
  '(((baz))                                       ;unload
    ())                                           ;load
  (call-with-values
      (lambda ()
        ;; Service 'bar' is not among the target services; yet, it must not be
        ;; unloaded because 'foo' depends on it.
        (service-upgrade (list (live-service '(foo) '(bar) #t)
                               (live-service '(bar) '() #t) ;still used!
                               (live-service '(baz) '() #t))
                         (list (shepherd-service (provision '(foo))
                                                 (start #t)))))
    (lambda (unload load)
      (list (map live-service-provision unload)
            (map shepherd-service-provision load)))))

(test-equal "service-upgrade: obsolete services that depend on each other"
  '(((foo) (bar) (baz))                           ;unload
    ((qux)))                                      ;load
  (call-with-values
      (lambda ()
        ;; 'foo', 'bar', and 'baz' depend on each other, but all of them are
        ;; obsolete, and thus should be unloaded.
        (service-upgrade (list (live-service '(foo) '(bar) #t) ;obsolete
                               (live-service '(bar) '(baz) #t) ;obsolete
                               (live-service '(baz) '() #t))   ;obsolete
                         (list (shepherd-service (provision '(qux))
                                                 (start #t)))))
    (lambda (unload load)
      (list (map live-service-provision unload)
            (map shepherd-service-provision load)))))

(test-end)
