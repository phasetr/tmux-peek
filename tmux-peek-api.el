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

;; Public async API.  Only `kill-session' is exposed for cleanup; window,
;; pane, and server cleanup commands are intentionally absent.

;;; Code:

(require 'tmux-peek-async)
(require 'tmux-peek-command)
(require 'tmux-peek-parse)
(require 'subr-x)

(defun tmux-peek--map-result (callback mapper)
  "Return CALLBACK wrapper that maps a successful result through MAPPER."
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
When OPTS is non-nil, pass it to the async executor.  When MAPPER is non-nil,
use it to build `:value' from stdout."
  (tmux-peek--exec-async
   (tmux-peek--tmux-executable opts)
   args
   (if mapper (tmux-peek--map-result callback mapper) callback)
   opts))

(defun tmux-peek--list-command-async (command fields parser callback opts)
  "Run tmux list COMMAND using FIELDS, PARSER, CALLBACK, and OPTS."
  (tmux-peek--run-tmux-async
   (tmux-peek--list-args command fields opts)
   callback opts
   (lambda (stdout) (funcall parser stdout fields))))

(defun tmux-peek--result-has-value-p (result)
  "Return non-nil when RESULT has a non-empty `:value'."
  (not (string-empty-p (string-trim-right
                        (or (plist-get result :value) "")))))

(defun tmux-peek-list-sessions-async (callback &optional opts)
  "Asynchronously list tmux sessions.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-session-fields)))
    (tmux-peek--list-command-async
     "list-sessions" fields #'tmux-peek--parse-list-sessions callback opts)))

(defun tmux-peek-list-windows-async (callback &optional opts)
  "Asynchronously list tmux windows.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-window-fields)))
    (tmux-peek--list-command-async
     "list-windows" fields #'tmux-peek--parse-list-windows callback opts)))

(defun tmux-peek-list-panes-async (callback &optional opts)
  "Asynchronously list tmux panes.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-pane-fields)))
    (tmux-peek--list-command-async
     "list-panes" fields #'tmux-peek--parse-list-panes callback opts)))

(defun tmux-peek-list-clients-async (callback &optional opts)
  "Asynchronously list tmux clients.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-client-fields)))
    (tmux-peek--list-command-async
     "list-clients" fields #'tmux-peek--parse-list-clients callback opts)))

(defun tmux-peek-list-buffers-async (callback &optional opts)
  "Asynchronously list tmux paste buffers.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((fields (or (plist-get opts :fields) tmux-peek-default-buffer-fields)))
    (tmux-peek--list-command-async
     "list-buffers" fields #'tmux-peek--parse-list-buffers callback opts)))

(defun tmux-peek-display-message-async (format callback &optional opts)
  "Asynchronously expand tmux FORMAT using display-message.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (tmux-peek--run-tmux-async
   (tmux-peek--display-message-args format opts)
   callback opts
   #'string-trim-right))

(defun tmux-peek-capture-pane-async (callback &optional opts)
  "Asynchronously capture a tmux pane.
CALLBACK receives a result plist.  OPTS may include `:target' and
`:tail-lines'."
  (tmux-peek--run-tmux-async
   (tmux-peek--capture-pane-args opts)
   callback opts
   #'identity))

(defun tmux-peek-show-buffer-async (callback &optional opts)
  "Asynchronously show a tmux paste buffer.
CALLBACK receives a result plist.  OPTS may include `:buffer-name'."
  (tmux-peek--run-tmux-async
   (tmux-peek--show-buffer-args opts)
   callback opts
   #'identity))

(defun tmux-peek-show-options-async (callback &optional opts)
  "Asynchronously show tmux options.
CALLBACK receives a result plist.  OPTS may include `:global', `:window',
`:target', and `:option'."
  (tmux-peek--run-tmux-async
   (tmux-peek--show-options-args opts)
   callback opts
   #'tmux-peek--parse-show-options))

(defun tmux-peek-show-environment-async (callback &optional opts)
  "Asynchronously show tmux environment.
CALLBACK receives a result plist.  OPTS may include `:global', `:target', and
`:variable'."
  (tmux-peek--run-tmux-async
   (tmux-peek--show-environment-args opts)
   callback opts
   #'tmux-peek--parse-show-environment))

(defun tmux-peek-server-running-p-async (callback &optional opts)
  "Asynchronously report whether a tmux server is running.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (tmux-peek-list-sessions-async
   (lambda (result)
     (if (plist-get result :ok)
         (funcall callback (list :ok t :value t :source result))
       (if (eq (plist-get result :error) 'tmux-peek-error-no-server)
           (funcall callback
                    (list :ok t
                          :value nil
                          :source result))
         (funcall callback result))))
   opts))

(defun tmux-peek-version-async (callback &optional opts)
  "Asynchronously return the tmux version string.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (tmux-peek--run-tmux-async
   '("-V") callback opts #'string-trim-right))

(defun tmux-peek-target-exists-p-async (target callback &optional opts)
  "Asynchronously report whether TARGET exists.
CALLBACK receives a result plist.  OPTS may override common tmux options."
  (let ((opts (plist-put (copy-sequence opts) :target target)))
    (tmux-peek-display-message-async
     "#{pane_id}"
     (lambda (result)
       (funcall callback
                (if (plist-get result :ok)
                    (list :ok t
                          :value (tmux-peek--result-has-value-p result)
                          :source result)
                  (if (eq (plist-get result :error) 'tmux-peek-error-no-target)
                      (list :ok t :value nil :source result)
                    result))))
     opts)))

(defun tmux-peek-kill-session-async (target callback &optional opts)
  "Asynchronously kill the tmux session TARGET.
CALLBACK receives a result plist.  OPTS may override common tmux options.
This package intentionally does not expose kill-pane, kill-window, or
kill-server wrappers."
  (let ((opts (plist-put (copy-sequence opts) :target target)))
    (tmux-peek--run-tmux-async
     (tmux-peek--kill-session-args opts)
     callback opts
     (lambda (_stdout) t))))

(provide 'tmux-peek-api)
;;; tmux-peek-api.el ends here
