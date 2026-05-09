;;; tmux-peek-command.el --- tmux argument builders -*- lexical-binding: t; -*-

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

;; Builds tmux command argument lists.  Only session-level cleanup is exposed;
;; window, pane, and server cleanup commands are intentionally absent.

;;; Code:

(require 'subr-x)

(defcustom tmux-peek-tmux-executable "tmux"
  "Path to the tmux executable."
  :type 'string
  :group 'tmux-peek)

(defcustom tmux-peek-default-socket-name nil
  "Default tmux socket name for `-L'."
  :type '(choice (const nil) string)
  :group 'tmux-peek)

(defconst tmux-peek--field-separator "|||")

(defconst tmux-peek-default-session-fields
  '((:key :name :format "session_name" :type string)
    (:key :id :format "session_id" :type string)
    (:key :windows :format "session_windows" :type integer)
    (:key :attached :format "session_attached" :type boolean)
    (:key :created :format "session_created" :type integer)))

(defconst tmux-peek-default-window-fields
  '((:key :session :format "session_name" :type string)
    (:key :index :format "window_index" :type integer)
    (:key :name :format "window_name" :type string)
    (:key :id :format "window_id" :type string)
    (:key :active :format "window_active" :type boolean)
    (:key :panes :format "window_panes" :type integer)))

(defconst tmux-peek-default-pane-fields
  '((:key :session :format "session_name" :type string)
    (:key :window-index :format "window_index" :type integer)
    (:key :pane-index :format "pane_index" :type integer)
    (:key :pane-id :format "pane_id" :type string)
    (:key :pane-pid :format "pane_pid" :type integer)
    (:key :current-command :format "pane_current_command" :type string)
    (:key :current-path :format "pane_current_path" :type string)
    (:key :active :format "pane_active" :type boolean)
    (:key :width :format "pane_width" :type integer)
    (:key :height :format "pane_height" :type integer)))

(defconst tmux-peek-default-client-fields
  '((:key :name :format "client_name" :type string)
    (:key :tty :format "client_tty" :type string)
    (:key :session :format "client_session" :type string)
    (:key :pid :format "client_pid" :type integer)
    (:key :width :format "client_width" :type integer)
    (:key :height :format "client_height" :type integer)
    (:key :created :format "client_created" :type integer)))

(defconst tmux-peek-default-buffer-fields
  '((:key :name :format "buffer_name" :type string)
    (:key :size :format "buffer_size" :type integer)
    (:key :created :format "buffer_created" :type integer)
    (:key :sample :format "buffer_sample" :type string)))

(defun tmux-peek--tmux-executable (&optional opts)
  "Return tmux executable from OPTS or customization."
  (or (plist-get opts :tmux-executable)
      tmux-peek-tmux-executable))

(defun tmux-peek--socket-args (&optional opts)
  "Return socket arguments from OPTS."
  (let ((socket-name (or (plist-get opts :socket-name)
                         tmux-peek-default-socket-name))
        (socket-path (plist-get opts :socket-path)))
    (cond
     ((and socket-name socket-path)
      (user-error "Use only one of :socket-name and :socket-path"))
     (socket-name (list "-L" socket-name))
     (socket-path (list "-S" socket-path))
     (t nil))))

(defun tmux-peek--target-args (&optional opts)
  "Return target args from OPTS."
  (when-let* ((target (plist-get opts :target)))
    (list "-t" target)))

(defun tmux-peek--build-args (command &optional opts command-args)
  "Build tmux args for COMMAND using OPTS and COMMAND-ARGS."
  (append (tmux-peek--socket-args opts)
          (list command)
          command-args))

(defun tmux-peek--normalize-field (field)
  "Normalize FIELD into a field definition plist."
  (cond
   ((stringp field)
    (list :key (intern (concat ":" (replace-regexp-in-string "_" "-" field)))
          :format field
          :type 'string))
   ((and (consp field) (plist-get field :key) (plist-get field :format))
    field)
   (t (user-error "Invalid tmux-peek field: %S" field))))

(defun tmux-peek--format-spec (fields)
  "Return tmux `-F' format string for FIELDS."
  (mapconcat
   (lambda (field)
     (format "#{%s}" (plist-get (tmux-peek--normalize-field field) :format)))
   fields
   tmux-peek--field-separator))

(defun tmux-peek--list-args (command fields &optional opts)
  "Build args for a list COMMAND using FIELDS and OPTS."
  (tmux-peek--build-args
   command opts
   (append (tmux-peek--target-args opts)
           (list "-F" (tmux-peek--format-spec fields)))))

(defun tmux-peek--display-message-args (format &optional opts)
  "Build args for tmux display-message FORMAT and OPTS."
  (tmux-peek--build-args
   "display-message" opts
   (append (list "-p")
           (tmux-peek--target-args opts)
           (list format))))

(defun tmux-peek--capture-pane-args (&optional opts)
  "Build args for tmux capture-pane and OPTS."
  (let ((tail-lines (plist-get opts :tail-lines)))
    (tmux-peek--build-args
     "capture-pane" opts
     (append (list "-p" "-J")
             (tmux-peek--target-args opts)
             (when tail-lines
               (list "-S" (format "-%d" tail-lines)))))))

(defun tmux-peek--show-buffer-args (&optional opts)
  "Build args for tmux show-buffer and OPTS."
  (tmux-peek--build-args
   "show-buffer" opts
   (when-let* ((buffer-name (plist-get opts :buffer-name)))
     (list "-b" buffer-name))))

(defun tmux-peek--show-options-args (&optional opts)
  "Build args for tmux show-options and OPTS."
  (tmux-peek--build-args
   "show-options" opts
   (append (when (plist-get opts :global) (list "-g"))
           (when (plist-get opts :window) (list "-w"))
           (tmux-peek--target-args opts)
           (when-let* ((option (plist-get opts :option)))
             (list option)))))

(defun tmux-peek--show-environment-args (&optional opts)
  "Build args for tmux show-environment and OPTS."
  (tmux-peek--build-args
   "show-environment" opts
   (append (when (plist-get opts :global) (list "-g"))
           (tmux-peek--target-args opts)
           (when-let* ((variable (plist-get opts :variable)))
             (list variable)))))

(defun tmux-peek--kill-session-args (&optional opts)
  "Build args for tmux kill-session and OPTS."
  (unless (plist-get opts :target)
    (user-error "`tmux-peek-kill-session-async' requires :target"))
  (tmux-peek--build-args "kill-session" opts (tmux-peek--target-args opts)))

(provide 'tmux-peek-command)
;;; tmux-peek-command.el ends here
