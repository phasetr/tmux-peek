;;; tmux-peek-parse.el --- parsers for tmux-peek -*- lexical-binding: t; -*-

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

;; Minimal structured parsing for tmux list commands.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tmux-peek-command)
(require 'tmux-peek-error)

(defun tmux-peek--convert-value (value type)
  "Convert string VALUE according to TYPE."
  (pcase type
    ('integer
     (if (string-match-p (rx bos (? "-") (+ digit) eos) value)
         (string-to-number value)
       (signal 'tmux-peek-error-parse (list (format "Invalid integer: %S" value)))))
    ('boolean
     (cond
      ((member value '("1" "yes" "on" "true")) t)
      ((member value '("0" "no" "off" "false" "")) nil)
      (t (signal 'tmux-peek-error-parse (list (format "Invalid boolean: %S" value))))))
    (_ value)))

(defun tmux-peek--parse-list (stdout fields)
  "Parse list command STDOUT according to FIELDS."
  (let* ((fields (mapcar #'tmux-peek--normalize-field fields))
         (expected (length fields))
         (lines (split-string (string-trim-right (or stdout "")) "\n" t)))
    (mapcar
     (lambda (line)
       (let ((values (split-string line (regexp-quote tmux-peek--field-separator))))
         (unless (= (length values) expected)
           (signal 'tmux-peek-error-parse
                   (list (format "Expected %d fields, got %d in %S"
                                 expected (length values) line))))
         (let (plist)
           (cl-mapc
            (lambda (field value)
              (setq plist
                    (plist-put plist
                               (plist-get field :key)
                               (tmux-peek--convert-value
                                value (plist-get field :type)))))
            fields values)
           plist)))
     lines)))

(defun tmux-peek--parse-list-sessions (stdout &optional fields)
  "Parse list-sessions STDOUT."
  (tmux-peek--parse-list stdout (or fields tmux-peek-default-session-fields)))

(defun tmux-peek--parse-list-windows (stdout &optional fields)
  "Parse list-windows STDOUT."
  (tmux-peek--parse-list stdout (or fields tmux-peek-default-window-fields)))

(defun tmux-peek--parse-list-panes (stdout &optional fields)
  "Parse list-panes STDOUT."
  (tmux-peek--parse-list stdout (or fields tmux-peek-default-pane-fields)))

(provide 'tmux-peek-parse)
;;; tmux-peek-parse.el ends here
