;;; tmux-peek-api.el --- Public API for tmux-peek -*- lexical-binding: t; -*-

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

;; Public async API.  Only `kill-pane' is exposed for cleanup; broader kill
;; commands are intentionally absent.

;;; Code:

(require 'tmux-peek-async)
(require 'tmux-peek-command)
(require 'tmux-peek-parse)

(defun tmux-peek--map-result (callback mapper)
  "Return callback that maps a successful result through MAPPER."
  (lambda (result)
    (if (plist-get result :ok)
        (condition-case err
            (funcall callback
                     (plist-put result :value
                                (funcall mapper (plist-get result :stdout))))
          (tmux-peek-error
           (funcall callback
                    (list :ok nil
                          :error (car err)
                          :stdout (plist-get result :stdout)
                          :stderr (or (cadr err) "")
                          :exit-code (plist-get result :exit-code)
                          :command (plist-get result :command)))))
      (funcall callback result))))

(defun tmux-peek--run-tmux-async (args callback &optional opts mapper)
  "Run tmux ARGS and call CALLBACK.
When MAPPER is non-nil, use it to build `:value' from stdout."
  (tmux-peek--exec-async
   (tmux-peek--tmux-executable opts)
   args
   (if mapper (tmux-peek--map-result callback mapper) callback)
   opts))

(defun tmux-peek-list-sessions-async (callback &optional opts)
  "Asynchronously list tmux sessions."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-session-fields)))
    (tmux-peek--run-tmux-async
     (tmux-peek--list-args "list-sessions" fields opts)
     callback opts
     (lambda (stdout) (tmux-peek--parse-list-sessions stdout fields)))))

(defun tmux-peek-list-windows-async (callback &optional opts)
  "Asynchronously list tmux windows."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-window-fields)))
    (tmux-peek--run-tmux-async
     (tmux-peek--list-args "list-windows" fields opts)
     callback opts
     (lambda (stdout) (tmux-peek--parse-list-windows stdout fields)))))

(defun tmux-peek-list-panes-async (callback &optional opts)
  "Asynchronously list tmux panes."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-pane-fields)))
    (tmux-peek--run-tmux-async
     (tmux-peek--list-args "list-panes" fields opts)
     callback opts
     (lambda (stdout) (tmux-peek--parse-list-panes stdout fields)))))

(defun tmux-peek-display-message-async (format callback &optional opts)
  "Asynchronously expand tmux FORMAT using display-message."
  (tmux-peek--run-tmux-async
   (tmux-peek--display-message-args format opts)
   callback opts
   #'string-trim-right))

(defun tmux-peek-capture-pane-async (callback &optional opts)
  "Asynchronously capture a tmux pane.
OPTS may include `:target' and `:tail-lines'."
  (tmux-peek--run-tmux-async
   (tmux-peek--capture-pane-args opts)
   callback opts
   #'identity))

(defun tmux-peek-show-buffer-async (callback &optional opts)
  "Asynchronously show a tmux paste buffer."
  (tmux-peek--run-tmux-async
   (tmux-peek--show-buffer-args opts)
   callback opts
   #'identity))

(defun tmux-peek-server-running-p-async (callback &optional opts)
  "Asynchronously report whether a tmux server is running."
  (tmux-peek-list-sessions-async
   (lambda (result)
     (if (plist-get result :ok)
         (funcall callback (list :ok t :value t :source result))
       (funcall callback
                (list :ok t
                      :value nil
                      :source result))))
   opts))

(defun tmux-peek-version-async (callback &optional opts)
  "Asynchronously return the tmux version string."
  (tmux-peek--run-tmux-async
   '("-V") callback opts #'string-trim-right))

(defun tmux-peek-target-exists-p-async (target callback &optional opts)
  "Asynchronously report whether TARGET exists."
  (let ((opts (plist-put (copy-sequence opts) :target target)))
    (tmux-peek-display-message-async
     "#{pane_id}"
     (lambda (result)
       (funcall callback
                (if (plist-get result :ok)
                    (list :ok t :value t :source result)
                  (list :ok t :value nil :source result))))
     opts)))

(defun tmux-peek-kill-pane-async (target callback &optional opts)
  "Asynchronously kill the tmux pane TARGET.
This package intentionally does not expose kill-session, kill-window, or
kill-server wrappers."
  (let ((opts (plist-put (copy-sequence opts) :target target)))
    (tmux-peek--run-tmux-async
     (tmux-peek--kill-pane-args opts)
     callback opts
     (lambda (_stdout) t))))

(provide 'tmux-peek-api)
;;; tmux-peek-api.el ends here
