;;; tmux-peek-error.el --- Error helpers for tmux-peek -*- lexical-binding: t; -*-

;; Copyright (C) 2026 phasetr

;; This file is part of tmux-peek.

;; tmux-peek is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.

;; tmux-peek is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.

;; You should have received a copy of the GNU General Public License along
;; with tmux-peek.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Error symbols and stderr classification.

;;; Code:

(require 'subr-x)

(define-error 'tmux-peek-error "tmux-peek error")
(define-error 'tmux-peek-error-not-found "tmux executable not found" 'tmux-peek-error)
(define-error 'tmux-peek-error-no-server "tmux server is not running" 'tmux-peek-error)
(define-error 'tmux-peek-error-no-target "tmux target was not found" 'tmux-peek-error)
(define-error 'tmux-peek-error-timeout "tmux command timed out" 'tmux-peek-error)
(define-error 'tmux-peek-error-parse "tmux output parse error" 'tmux-peek-error)
(define-error 'tmux-peek-error-exec "tmux command failed" 'tmux-peek-error)

(defun tmux-peek--classify-stderr (stderr)
  "Return a tmux-peek error symbol for STDERR."
  (let ((text (or stderr "")))
    (cond
     ((string-match-p "no server running" text)
      'tmux-peek-error-no-server)
     ((string-match-p
       (rx (or "can't find session"
               "can't find window"
               "can't find pane"
               "can't find client"
               "no such session"
               "no such window"
               "no such pane"))
       text)
      'tmux-peek-error-no-target)
     (t 'tmux-peek-error-exec))))

(provide 'tmux-peek-error)
;;; tmux-peek-error.el ends here
