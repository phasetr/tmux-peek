;;; tmux-peek-session-list.el --- Session list UI for tmux-peek -*- lexical-binding: t; -*-

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

;; Tabulated session list for inspecting and explicitly killing tmux sessions.

;;; Code:

(require 'tabulated-list)
(require 'tmux-peek-api)

(defcustom tmux-peek-session-list-buffer-name "*tmux-peek sessions*"
  "Buffer name for the tmux-peek session list."
  :type 'string
  :group 'tmux-peek)

(defvar-local tmux-peek-session-list--opts nil)
(defvar-local tmux-peek-session-list--last-result nil)

(defvar-keymap tmux-peek-session-list-mode-map
  :doc "Keymap for `tmux-peek-session-list-mode'."
  :parent tabulated-list-mode-map
  "g" #'tmux-peek-session-list-refresh
  "r" #'tmux-peek-session-list-refresh
  "d" #'tmux-peek-session-list-kill
  "k" #'tmux-peek-session-list-kill
  "q" #'quit-window)

(define-derived-mode tmux-peek-session-list-mode tabulated-list-mode
  "tmux-peek-sessions"
  "Major mode for inspecting and killing tmux sessions."
  (setq tabulated-list-format
        [("Name" 24 t)
         ("Id" 8 t)
         ("Windows" 8 t)
         ("Attached" 8 t)
         ("Created" 12 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Name" nil))
  (tabulated-list-init-header))

(defun tmux-peek-session-list--string (value)
  "Return VALUE as a display string."
  (if value (format "%s" value) ""))

(defun tmux-peek-session-list--entry (session)
  "Return a tabulated-list entry for SESSION."
  (let ((name (tmux-peek-session-list--string (plist-get session :name))))
    (list name
          (vector
           name
           (tmux-peek-session-list--string (plist-get session :id))
           (tmux-peek-session-list--string (plist-get session :windows))
           (if (plist-get session :attached) "yes" "no")
           (tmux-peek-session-list--string (plist-get session :created))))))

(defun tmux-peek-session-list--session-at-point ()
  "Return the session name at point."
  (or (tabulated-list-get-id)
      (user-error "No tmux session on this line")))

(defun tmux-peek-session-list--apply-result (result)
  "Render list-sessions RESULT in the current buffer."
  (setq tmux-peek-session-list--last-result result)
  (setq tabulated-list-entries
        (when (plist-get result :ok)
          (mapcar #'tmux-peek-session-list--entry
                  (plist-get result :value))))
  (tabulated-list-print t)
  (unless (plist-get result :ok)
    (message "tmux-peek list sessions failed: %S"
             (plist-get result :error))))

(defun tmux-peek-session-list-refresh ()
  "Refresh the tmux session list."
  (interactive)
  (let ((buffer (current-buffer))
        (opts tmux-peek-session-list--opts))
    (tmux-peek-list-sessions-async
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (tmux-peek-session-list--apply-result result))))
     opts)))

(defun tmux-peek-session-list-kill (&optional session)
  "Kill SESSION, or the tmux session at point when SESSION is nil."
  (interactive)
  (let ((session (or session (tmux-peek-session-list--session-at-point)))
        (buffer (current-buffer))
        (opts tmux-peek-session-list--opts))
    (when (y-or-n-p (format "Kill tmux session %s? " session))
      (tmux-peek-kill-session-async
       session
       (lambda (result)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq tmux-peek-session-list--last-result result)
             (if (plist-get result :ok)
                 (progn
                   (message "Killed tmux session: %s" session)
                   (tmux-peek-session-list-refresh))
               (message "tmux-peek kill session failed: %S"
                        (plist-get result :error))))))
       opts))))

;;;###autoload
(defun tmux-peek-session-list (&optional opts)
  "Open a tmux session list buffer.
OPTS are passed to tmux-peek async commands."
  (interactive)
  (let ((buffer (get-buffer-create tmux-peek-session-list-buffer-name)))
    (with-current-buffer buffer
      (tmux-peek-session-list-mode)
      (setq tmux-peek-session-list--opts opts)
      (tmux-peek-session-list-refresh))
    (pop-to-buffer buffer)))

(provide 'tmux-peek-session-list)
;;; tmux-peek-session-list.el ends here
